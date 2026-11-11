import { BadRequestException, PayloadTooLargeException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';

export const ATTACHMENT_LIMIT = 20 * 1024 * 1024;
export interface AttachmentUpload {
  id: string;
  name: string;
  mimeType: string;
  data: Buffer;
  preview: Buffer | null;
  width: number | null;
  height: number | null;
}

export function safeFilename(name: string) {
  const clean = name
    .normalize('NFC')
    .replace(/\\/g, '/')
    .split('/')
    .pop()!
    .replace(/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g, '')
    .trim();
  return (
    Array.from(clean === '.' || clean === '..' ? '' : clean)
      .slice(0, 180)
      .join('') || 'attachment'
  );
}

export async function prepareAttachments(
  files: Express.Multer.File[] | undefined,
  namesJSON?: string,
): Promise<AttachmentUpload[]> {
  if (!files?.length || files.length > 5) throw new BadRequestException('请选择 1–5 个附件');
  if (files.some((f) => !f.buffer?.length)) throw new BadRequestException('不能发送空文件');
  if (files.reduce((size, f) => size + f.buffer.length, 0) > ATTACHMENT_LIMIT) {
    throw new PayloadTooLargeException('附件合计不能超过 20 MB');
  }
  let names: string[] = files.map((f) => f.originalname);
  if (namesJSON !== undefined) {
    try {
      const parsed = JSON.parse(namesJSON);
      if (
        !Array.isArray(parsed) ||
        parsed.length !== files.length ||
        parsed.some((n) => typeof n !== 'string' || n.length > 1000)
      )
        throw new Error();
      names = parsed;
    } catch {
      throw new BadRequestException('附件名称与文件数量不匹配');
    }
  }
  const result: AttachmentUpload[] = [];
  for (const [index, file] of files.entries()) {
    const attachment: AttachmentUpload = {
      id: randomUUID(),
      name: safeFilename(names[index]!),
      mimeType: 'application/octet-stream',
      data: file.buffer,
      preview: null,
      width: null,
      height: null,
    };
    // Only decoded raster images receive a preview. Other files are download-only.
    // Originals, including animation and metadata, are preserved byte-for-byte.
    try {
      const image = sharp(file.buffer, { limitInputPixels: 24_000_000, failOn: 'warning' });
      const metadata = await image.metadata();
      const formats: Record<string, string> = {
        jpeg: 'image/jpeg',
        png: 'image/png',
        webp: 'image/webp',
        gif: 'image/gif',
      };
      if (metadata.format && formats[metadata.format]) {
        const preview = await image
          .rotate()
          .resize({ width: 1600, height: 1600, fit: 'inside', withoutEnlargement: true })
          .webp({ quality: 85 })
          .toBuffer({ resolveWithObject: true });
        attachment.mimeType = formats[metadata.format]!;
        attachment.preview = preview.data;
        attachment.width = preview.info.width;
        attachment.height = preview.info.height;
      }
    } catch {
      /* Unsupported or oversized raster images remain downloadable originals. */
    }
    result.push(attachment);
  }
  return result;
}

// Metadata only: binary data is never included in message list queries.
export const attachmentMetadataSQL = `(SELECT json_group_array(json_object(
  'id',a.id,'name',a.name,'mimeType',a.mime_type,'size',a.size,
  'hasPreview',CASE WHEN a.preview_present=0 THEN json('false') ELSE json('true') END,
  'width',a.width,'height',a.height,'deletedAt',a.deleted_at)) FROM
  (SELECT id,name,mime_type,size,preview IS NOT NULL AS preview_present,width,height,deleted_at FROM message_attachments WHERE message_id=messages.id ORDER BY position) a)`;
