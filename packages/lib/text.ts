export const truncate = (text: string, maxLength: number, ellipsis = true) => {
  if (text.length <= maxLength) return text;

  return `${text.slice(0, maxLength - 3)}${ellipsis ? "..." : ""}`;
};

export const truncateOnWord = (text: string, maxLength: number, ellipsis = true) => {
  if (text.length <= maxLength) return text;

  // The ellipsis only fits when maxLength leaves room for it
  const withEllipsis = ellipsis && maxLength >= 3;

  // First split on maxLength chars, leaving room for the ellipsis
  const cutLength = withEllipsis ? maxLength - 3 : maxLength;
  let truncatedText = text.substring(0, cutLength);

  // Then split on the last space, this way we split on the last word,
  // which looks just a bit nicer. Keep the cut when it already ends on a
  // word, and keep the hard cut when there is no space.
  const lastSpaceIndex = truncatedText.lastIndexOf(" ");
  if (text[cutLength] !== " " && lastSpaceIndex > 0) {
    truncatedText = truncatedText.substring(0, lastSpaceIndex);
  }

  if (withEllipsis) truncatedText += "...";

  return truncatedText;
};
