#!/usr/bin/env bash
set -euo pipefail

# ============ 配置 ============
ADD_MB=2536                   # 追加容量（MiB），当前约 +2.48 GiB
P3_FS="ntfs"                  # 可选: ntfs | exfat
P3_LABEL="data"               # 新的分区3卷标
TMP_DIR="$(pwd)/tmp"          # 备份/恢复目录；脚本会创建、用完后删除
# =============================

if [[ $# -lt 1 ]]; then
  echo "用法: $0 <镜像文件路径>"
  exit 1
fi
IMG="$1"
[[ -f "$IMG" ]] || { echo "找不到镜像: $IMG"; exit 1; }

# 运行期资源（挂载点等）
P3_OLD_MNT="$(mktemp -d -t p3_old.XXXXXX)"
P3_NEW_MNT="$(mktemp -d -t p3_new.XXXXXX)"
LOOP=""

settle() {
  # 等待内核/udev 创建设备节点；在 WSL 等无 udev 环境用 sleep 兜底
  if command -v udevadm >/dev/null 2>&1; then
    sudo udevadm settle || true
  else
    sleep 1
  fi
}

cleanup() {
  set +e
  mountpoint -q "$P3_OLD_MNT" && sudo umount "$P3_OLD_MNT"
  mountpoint -q "$P3_NEW_MNT" && sudo umount "$P3_NEW_MNT"
  [[ -d "$P3_OLD_MNT" ]] && rmdir "$P3_OLD_MNT" || true
  [[ -d "$P3_NEW_MNT" ]] && rmdir "$P3_NEW_MNT" || true
  # 解绑当前 loop
  if [[ -n "${LOOP:-}" ]] && losetup -a | grep -q "^$LOOP:"; then
    sudo losetup -d "$LOOP" || true
  fi
}
trap cleanup EXIT

# 解除所有已映射到该镜像的 loop（如果存在）
echo "== 解除旧 loop（如果存在） =="
while read -r dev; do
  [[ -n "$dev" ]] && sudo losetup -d "$dev" || true
done < <(losetup -j "$IMG" | cut -d: -f1)

# 映射镜像到 loop（同时启用分区扫描），原子返回唯一设备名
echo "== 映射镜像到 loop（带分区） =="
LOOP="$(sudo losetup --find --show -P "$IMG")"
settle
echo "使用 loop: $LOOP"

# 扇区信息
SECTOR_SIZE="$(sudo blockdev --getss "$LOOP")"  # 常见 512
ADD_BYTES=$(( ADD_MB * 1024 * 1024 ))
ADD_SECTORS=$(( ADD_BYTES / SECTOR_SIZE ))

# 工具函数：检查 p3 是否存在（机器可读模式）
has_p3() {
  sudo parted -sm "$LOOP" unit s print | grep -qE '^3:'
}

# 读取 p2 结束扇区（机器可读更稳）
CUR_END="$(sudo parted -sm "$LOOP" unit s print | awk -F: '$1=="2"{gsub(/s/,"",$3); print $3}')"
[[ -n "${CUR_END:-}" ]] || { echo "未能读取到分区2信息，退出。"; exit 1; }
echo "当前 p2 End: $CUR_END"
echo "扇区大小: ${SECTOR_SIZE} B，扩容扇区数: ${ADD_SECTORS}"

# ======= 第一步：备份 p3 到 TMP_DIR（若存在） =======
if has_p3; then
  echo "检测到 p3，准备备份到 $TMP_DIR"
  mkdir -p "$TMP_DIR"
  P3_DEV="${LOOP}p3"

  echo "挂载旧 p3 到 $P3_OLD_MNT（优先只读）"
  if ! sudo mount -o ro "$P3_DEV" "$P3_OLD_MNT"; then
    echo "只读挂载失败，尝试普通挂载"
    sudo mount "$P3_DEV" "$P3_OLD_MNT"
  fi

  echo "备份 p3 -> $TMP_DIR（rsync -aH --delete，保证 tmp 为“镜像一致”）"
  sudo rsync -aH --delete --info=progress2 "$P3_OLD_MNT"/ "$TMP_DIR"/

  echo "卸载旧 p3 挂载点"
  sudo umount "$P3_OLD_MNT"
else
  echo "未发现 p3，跳过备份。"
fi

# ======= 第二步：删除 p3 分区（必须清路） =======
echo "== 删除旧的分区3 =="
if sudo parted -s "$LOOP" rm 3 2>/dev/null; then
  echo "已删除 p3（如果原本存在）"
else
  echo "未能删除 p3（可能原本就不存在），继续。"
fi

# 再次校验，若仍存在 p3 则终止
if has_p3; then
  echo "错误：p3 仍存在，无法继续扩容。请检查分区表后重试。"
  sudo parted "$LOOP" unit s print || true
  exit 1
fi

# ======= 第三步：扩展镜像文件并扩 p2 =======
echo "== 扩大镜像 +${ADD_MB}MiB =="
truncate -s +"${ADD_MB}"M "$IMG"

echo "== 刷新 loop 大小 =="
sudo losetup -d "$LOOP"
LOOP="$(sudo losetup --find --show -P "$IMG")"
settle
echo "loop 已刷新: $LOOP"

# 重新读取 p2 End（以防 parted/内核刷新导致边界变化）
CUR_END="$(sudo parted -sm "$LOOP" unit s print | awk -F: '$1=="2"{gsub(/s/,"",$3); print $3}')"
[[ -n "${CUR_END:-}" ]] || { echo "刷新后未能读取到分区2信息，退出。"; exit 1; }
NEW_END=$(( CUR_END + ADD_SECTORS ))
echo "将 p2 结束扇区扩到: $NEW_END"

echo "== 扩展 p2 到指定扇区（非100%） =="
sudo parted -s "$LOOP" unit s "resizepart 2 ${NEW_END}s"
sudo partprobe "$LOOP" || true
settle

echo "== 扩展 p2 内文件系统（自动检测 ext4 / f2fs） =="
P2_DEV="${LOOP}p2"
P2_FS="$(blkid -s TYPE -o value "$P2_DEV" || true)"
case "$P2_FS" in
  ext4|"")
    sudo e2fsck -fy "$P2_DEV"
    sudo resize2fs "$P2_DEV"
    ;;
  f2fs)
    sudo fsck.f2fs -f "$P2_DEV" || true
    sudo resize.f2fs "$P2_DEV"
    ;;
  *)
    echo "警告：未知/不支持的 p2 文件系统类型：$P2_FS"
    echo "请手动扩展 p2 文件系统后再继续。"
    ;;
esac

# ======= 第四步：重建 p3（p2 尾后到盘尾） =======
echo "== 计算新 p3 起始扇区（p2 End + 1） =="
P2_END_NOW="$(sudo parted -sm "$LOOP" unit s print | awk -F: '$1=="2"{gsub(/s/,"",$3); print $3}')"
[[ -n "${P2_END_NOW:-}" ]] || { echo "未能读取最新 p2 End，退出。"; exit 1; }
P3_START=$(( P2_END_NOW + 1 ))
echo "p2 End: $P2_END_NOW"
echo "p3 Start: $P3_START"

echo "== 在尾部重建 p3 =="
sudo parted -s "$LOOP" unit s "mkpart primary ${P3_START}s 100%"
sudo partprobe "$LOOP" || true
settle

echo "== 格式化新的 p3 =="
P3_DEV="${LOOP}p3"
if [[ "$P3_FS" == "ntfs" ]]; then
  sudo mkfs.ntfs -F -L "$P3_LABEL" "$P3_DEV"
elif [[ "$P3_FS" == "exfat" ]]; then
  sudo mkfs.exfat -n "$P3_LABEL" "$P3_DEV"
else
  echo "不支持的 P3_FS: $P3_FS"
  exit 1
fi

# ======= 第五步：恢复数据（镜像一致） =======
if [[ -d "$TMP_DIR" ]] && [[ -n "$(ls -A "$TMP_DIR" 2>/dev/null || true)" ]]; then
  echo "== 恢复数据（镜像一致）：$TMP_DIR -> 新 p3 =="
  sudo mount "$P3_DEV" "$P3_NEW_MNT"
  sudo rsync -aH --delete --info=progress2 "$TMP_DIR"/ "$P3_NEW_MNT"/
  sync
  sudo umount "$P3_NEW_MNT"
  echo "恢复完成。"
else
  echo "没有找到备份内容，跳过恢复。"
fi

# ======= 第六步：可选检查输出 =======
echo "== 最终分区布局（MiB） =="
sudo parted "$LOOP" unit MiB print || true

# ======= 第七步：删除 tmp 并解绑 loop =======
echo "== 删除备份目录 $TMP_DIR =="
sudo rm -rf "$TMP_DIR"

echo "== 解绑 loop 设备 =="
sudo losetup -d "$LOOP" || true
LOOP=""

echo "✅ 完成：已按顺序【备份p3→删除p3→扩p2→重建p3→恢复→清理tmp→解绑loop】"
