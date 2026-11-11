export const MAX_ATTACHMENTS = 5;
export const MAX_ATTACHMENT_BYTES = 20 * 1024 * 1024;
export const previewImageTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
export function formatBytes(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
export function validateAttachments(files: File[]) {
  if (files.length > MAX_ATTACHMENTS) return '每条消息最多添加 5 个附件，请减少文件数量。';
  if (files.some((f) => f.size === 0)) return '无法发送空文件，请选择有内容的文件。';
  if (files.reduce((size, file) => size + file.size, 0) > MAX_ATTACHMENT_BYTES)
    return '附件总大小不能超过 20 MB，请减少文件或压缩后再试。';
  return null;
}
