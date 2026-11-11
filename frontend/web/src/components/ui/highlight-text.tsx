import { splitHighlight, type HighlightRange } from '@/lib/search-highlight';

export function HighlightText({
  text,
  query,
  ranges,
}: {
  text: string;
  query?: string;
  ranges?: HighlightRange[];
}) {
  return (
    <>
      {splitHighlight(text, query ?? '', ranges).map((part, index) =>
        part.highlighted ? (
          <mark className="search-highlight" key={index}>
            {part.text}
          </mark>
        ) : (
          part.text
        ),
      )}
    </>
  );
}
