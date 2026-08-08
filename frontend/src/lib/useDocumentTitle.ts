import { useEffect, useRef } from "react";

export function useDocumentTitle(title: string) {
  const previousTitle = useRef<string | null>(null);
  useEffect(() => {
    if (previousTitle.current === null) previousTitle.current = document.title;
    document.title = title;
    return () => {
      if (previousTitle.current !== null) document.title = previousTitle.current;
    };
  }, [title]);
}
