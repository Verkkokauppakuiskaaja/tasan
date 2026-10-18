import Anthropic from "@anthropic-ai/sdk";

import {
  EVENT_OUTPUT_SCHEMA,
  SYSTEM_PROMPT,
  buildUserPrompt,
} from "./prompt.js";

import {
  extractJsonObject,
} from "./jsonExtractor.js";

import {
  mapPayloadToEventDraft,
} from "./eventMapper.js";

const MAX_TOKENS = 6000;

/*
 * Tasan!'s own Claude call. Uses the official SDK and structured
 * outputs, so the reply is JSON matching EVENT_OUTPUT_SCHEMA and
 * no prefill or free-text parsing is needed.
 */
export async function extractEventWithClaude({
  ocrText,
  deviceContext,
  env,
}) {
  const apiKey =
    (env.CLAUDE_API_KEY || "")
      .trim();

  const model =
    (env.CLAUDE_MODEL || "")
      .trim();

  if (!apiKey) {
    throw new Error(
      "Missing CLAUDE_API_KEY"
    );
  }

  if (!model) {
    throw new Error(
      "Missing CLAUDE_MODEL"
    );
  }

  const client =
    new Anthropic({
      apiKey,
      maxRetries: 2,
      timeout: 55 * 1000,
    });

  const response =
    await client.messages.create({
      model,

      max_tokens:
        Number(env.MAX_TOKENS) || MAX_TOKENS,

      system:
        SYSTEM_PROMPT,

      output_config: {
        format: {
          type:
            "json_schema",

          schema:
            EVENT_OUTPUT_SCHEMA,
        },
      },

      messages: [
        {
          role:
            "user",

          content:
            buildUserPrompt(
              ocrText,
              deviceContext
            ),
        },
      ],
    });

  if (
    response.stop_reason === "refusal"
  ) {
    throw new Error(
      "Claude declined to read this text."
    );
  }

  if (
    response.stop_reason === "max_tokens"
  ) {
    throw new Error(
      "Claude response was cut off at max_tokens."
    );
  }

  const text =
    response.content
      .filter(
        (block) =>
          block.type === "text"
      )
      .map(
        (block) =>
          block.text
      )
      .join("");

  if (!text) {
    throw new Error(
      "Claude response did not contain text content. "
      + `stop_reason=${response.stop_reason}; `
      + `blocks=${response.content.map((block) => block.type).join(",")}`
    );
  }

  let eventPayload;

  try {
    eventPayload =
      JSON.parse(
        extractJsonObject(
          text
        )
      );

  } catch {
    throw new Error(
      `Claude returned invalid JSON: ${text.slice(0, 500)}`
    );
  }

  const result =
    mapPayloadToEventDraft(
      eventPayload,
      ocrText,
      deviceContext
    );

  if (
    !result
    || !Array.isArray(
      result.events
    )
    || result.events.length === 0
  ) {
    throw new Error(
      "Claude returned no usable event candidates."
    );
  }

  return result;
}
