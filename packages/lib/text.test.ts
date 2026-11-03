import { describe, expect, it } from "vitest";
import { truncate, truncateOnWord } from "./text";

describe("Text util tests", () => {
  describe("fn: truncate", () => {
    it("should return the original text when it is shorter than the max length", () => {
      const cases = [
        {
          input: "Hello world",
          maxLength: 100,
          expected: "Hello world",
        },
        {
          input: "Hello world",
          maxLength: 11,
          expected: "Hello world",
        },
      ];

      for (const { input, maxLength, expected } of cases) {
        const result = truncate(input, maxLength);

        expect(result).toEqual(expected);
      }
    });

    it("should return the truncated text when it is longer than the max length", () => {
      const cases = [
        {
          input: "Hello world",
          maxLength: 10,
          expected: "Hello w...",
        },
        {
          input: "Hello world",
          maxLength: 5,
          expected: "He...",
        },
      ];

      for (const { input, maxLength, expected } of cases) {
        const result = truncate(input, maxLength);

        expect(result).toEqual(expected);
      }
    });

    it("should return the truncated text without ellipsis when it is longer than the max length and ellipsis is false", () => {
      const cases = [
        {
          input: "Hello world",
          maxLength: 10,
          ellipsis: false,
          expected: "Hello w",
        },
        {
          input: "Hello world",
          maxLength: 5,
          ellipsis: false,
          expected: "He",
        },
      ];

      for (const { input, maxLength, ellipsis, expected } of cases) {
        const result = truncate(input, maxLength, ellipsis);

        expect(result).toEqual(expected);
      }
    });
  });

  describe("fn: truncateOnWord", () => {
    it("should return the original text when it is shorter than the max length", () => {
      const cases = [
        {
          input: "Hello world",
          maxLength: 100,
          expected: "Hello world",
        },
        {
          input: "Hello world",
          maxLength: 11,
          expected: "Hello world",
        },
      ];

      for (const { input, maxLength, expected } of cases) {
        const result = truncateOnWord(input, maxLength);

        expect(result).toEqual(expected);
      }
    });

    it("should return the text cut on the last space when it is longer than the max length", () => {
      const cases = [
        {
          input: "The quick brown fox jumps over the lazy dog",
          maxLength: 20,
          expected: "The quick brown...",
        },
        {
          input: "Hello world",
          maxLength: 10,
          expected: "Hello...",
        },
      ];

      for (const { input, maxLength, expected } of cases) {
        const result = truncateOnWord(input, maxLength);

        expect(result).toEqual(expected);
        expect(result.length).toBeLessThanOrEqual(maxLength);
      }
    });

    it("should return the text cut on the last space without ellipsis when ellipsis is false", () => {
      const cases = [
        {
          input: "The quick brown fox jumps over the lazy dog",
          maxLength: 20,
          ellipsis: false,
          expected: "The quick brown fox",
        },
        {
          input: "Hello world",
          maxLength: 10,
          ellipsis: false,
          expected: "Hello",
        },
      ];

      for (const { input, maxLength, ellipsis, expected } of cases) {
        const result = truncateOnWord(input, maxLength, ellipsis);

        expect(result).toEqual(expected);
        expect(result.length).toBeLessThanOrEqual(maxLength);
      }
    });

    it("should cut a long text to at most 158 characters on a word boundary", () => {
      const input = "Lorem ipsum dolor sit amet consectetur adipiscing elit ".repeat(5);

      const result = truncateOnWord(input, 158);
      const cutText = result.slice(0, -3);

      expect(result).toEqual(`${input.slice(0, 148)}...`);
      expect(result.length).toBeLessThanOrEqual(158);
      expect(input.startsWith(cutText)).toBe(true);
      expect(input[cutText.length]).toEqual(" ");
    });
  });
});
