/** One-lookahead host scanner for the binding capacity experiment, not production. */
export interface Token {
  text: string;
  part: number;
  offset: number;
  kind: "atom" | "string" | "punct" | "eof";
}
export class SourceTokens {
  private at = 0;
  private current: Token | undefined;
  fetched = 0;
  constructor(readonly source: string, readonly part: number) {}
  peek(): Token {
    if (this.current) return this.current;
    while (this.at < this.source.length) {
      const c = this.source[this.at];
      if (/\s/.test(c)) {
        this.at++;
        continue;
      }
      if (c === ";") {
        while (this.at < this.source.length && this.source[this.at] !== "\n") {
          this.at++;
        }
        continue;
      }
      break;
    }
    const offset = this.at;
    let kind: Token["kind"] = "atom";
    const first = this.source[this.at];
    if (first === undefined) kind = "eof";
    else if ("()'".includes(first)) {
      this.at++;
      kind = "punct";
    } else if (first === '"') {
      kind = "string";
      this.at++;
      while (true) {
        if (this.at >= this.source.length) {
          throw new Error("unterminated string");
        }
        const c = this.source[this.at++];
        if (c === '"') break;
        if (c === "\\") {
          if (this.at >= this.source.length) {
            throw new Error("unterminated escape");
          }
          this.at++;
        }
      }
    } else if (this.source.slice(this.at, this.at + 2) === "#\\") {
      this.at += 2;
      if (this.at >= this.source.length) throw new Error("missing character");
      // A delimiter can itself be the single character, e.g. #\(.
      this.at++;
      while (
        this.at < this.source.length && !/[\s()';]/.test(this.source[this.at])
      ) this.at++;
    } else {
      while (
        this.at < this.source.length && !/[\s()';]/.test(this.source[this.at])
      ) this.at++;
    }
    this.fetched++;
    return this.current = {
      text: this.source.slice(offset, this.at),
      part: this.part,
      offset,
      kind,
    };
  }
  take(): Token {
    const token = this.peek();
    this.current = undefined;
    return token;
  }
  expect(text: string) {
    const token = this.take();
    if (token.text !== text) {
      throw new Error(`${token.part}:${token.offset}: expected ${text}`);
    }
    return token;
  }
}
