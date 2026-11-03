export const truncate = (text: string, maxLength: number, ellipsis = true) => {
  if (text.length <= maxLength) return text;

  return `${text.slice(0, maxLength - 3)}${ellipsis ? "..." : ""}`;
};

export const truncateOnWord = (text: string, maxLength: number, ellipsis = true) => {
  if (text.length <= maxLength) return text;

  // First split on maxLength chars, leaving room for the ellipsis
  let truncatedText = text.substring(0, ellipsis ? maxLength - 3 : maxLength);

  // Then split on the last space, this way we split on the last word,
  // which looks just a bit nicer. Without a space, keep the hard cut.
  const lastSpaceIndex = truncatedText.lastIndexOf(" ");
  if (lastSpaceIndex > 0) truncatedText = truncatedText.substring(0, lastSpaceIndex);

  if (ellipsis) truncatedText += "...";

  return truncatedText;
};
