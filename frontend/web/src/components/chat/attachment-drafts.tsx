import { useEffect, useState } from 'react';
import { FileText, X } from 'lucide-react';
import { formatBytes, previewImageTypes } from '@/lib/attachments';

function DraftFile({
  file,
  remove,
  disabled,
}: {
  file: File;
  remove: () => void;
  disabled: boolean;
}) {
  const [url, setUrl] = useState('');
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    if (!previewImageTypes.includes(file.type)) return;
    const objectURL = URL.createObjectURL(file);
    setUrl(objectURL);
    return () => URL.revokeObjectURL(objectURL);
  }, [file]);
  return (
    <div className="attachment-draft">
      {url && !failed ? (
        <img src={url} alt={`待发送：${file.name}`} onError={() => setFailed(true)} />
      ) : (
        <FileText className="attachment-file-icon" size={26} />
      )}
      <div className="attachment-file-info">
        <strong title={file.name}>{file.name || '粘贴的图片'}</strong>
        <small>{formatBytes(file.size)}</small>
      </div>
      <button
        type="button"
        aria-label={`移除附件 ${file.name}`}
        disabled={disabled}
        onClick={remove}
      >
        <X size={16} />
      </button>
    </div>
  );
}
export function AttachmentDrafts({
  files,
  disabled,
  remove,
}: {
  files: File[];
  disabled: boolean;
  remove: (file: File) => void;
}) {
  if (!files.length) return null;
  return (
    <section className="attachment-drafts" aria-label="待发送附件">
      <div className="attachment-drafts-header">
        <strong>{files.length} 个附件待发送</strong>
        <span>{formatBytes(files.reduce((sum, f) => sum + f.size, 0))} / 20 MB</span>
      </div>
      <div className="attachment-draft-list">
        {files.map((file, index) => (
          <DraftFile
            key={`${file.name}-${file.size}-${file.lastModified}-${index}`}
            file={file}
            disabled={disabled}
            remove={() => remove(file)}
          />
        ))}
      </div>
    </section>
  );
}
