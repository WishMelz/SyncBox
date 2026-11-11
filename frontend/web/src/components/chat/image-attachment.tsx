import { useEffect, useState } from 'react';
import { X } from 'lucide-react';
export const imageTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
export function ImageAttachment({
  file,
  disabled,
  remove,
}: {
  file: File;
  disabled: boolean;
  remove: () => void;
}) {
  const [url, setUrl] = useState('');
  useEffect(() => {
    const value = URL.createObjectURL(file);
    setUrl(value);
    return () => URL.revokeObjectURL(value);
  }, [file]);
  return (
    <div className="image-attachment">
      {url && <img src={url} alt="待发送图片" />}
      <div>
        <strong>{file.name || '粘贴的图片'}</strong>
        <small>{(file.size / 1024).toFixed(0)} KB · 图片待发送</small>
      </div>
      <button type="button" aria-label="移除待发送图片" disabled={disabled} onClick={remove}>
        <X size={18} />
      </button>
    </div>
  );
}
