export function BrandIcon({ size = 32 }: { size?: number }) {
  return (
    <img
      src="/brand/syncbox-icon.svg"
      width={size}
      height={size}
      alt=""
      aria-hidden="true"
      style={{ borderRadius: '22%', flexShrink: 0 }}
    />
  );
}
