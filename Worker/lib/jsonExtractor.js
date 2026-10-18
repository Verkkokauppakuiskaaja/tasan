export function extractClaudeText(payload) {
  const content = Array.isArray(payload?.content) ? payload.content : [];
  return content
    .map((block) => (typeof block?.text === "string" ? block.text : ""))
    .join("\n")
    .trim();
}

export function extractJsonObject(text) {
  const cleaned = text
    .replace(/```json/gi, "")
    .replace(/```/g, "")
    .trim();

  const start = cleaned.indexOf("{");
  if (start === -1) {
    throw new Error(`Could not find JSON object in Claude text: ${cleaned}`);
  }

  let depth = 0;
  let inString = false;
  let escape = false;

  for (let i = start; i < cleaned.length; i++) {
    const ch = cleaned[i];

    if (inString) {
      if (escape) {
        escape = false;
      } else if (ch === "\\") {
        escape = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }

    if (ch === '"') {
      inString = true;
      continue;
    }

    if (ch === "{") {
      depth++;
    } else if (ch === "}") {
      depth--;
      if (depth === 0) {
        return cleaned.slice(start, i + 1);
      }
    }
  }

  throw new Error(`Could not find complete JSON object in Claude text: ${cleaned}`);
}