import {
  PROMPT_VERSION,
} from "./lib/prompt.js";

import {
  normalizeDeviceContext,
} from "./lib/deviceContext.js";

import {
  extractEventWithClaude,
} from "./lib/anthropic.js";

const WORKER_VERSION =
  "1.0";

const MAX_EVENTS =
  10;

const MAX_BODY_BYTES =
  64 * 1024;

const MAX_OCR_CHARS =
  10000;

/*
 * The app sends a shared key in X-Tasan-Key. It is not a
 * secret in the strict sense (it ships inside the app), but it
 * keeps casual scanners and bots from spending Claude credits.
 * Fails closed: without APP_KEY configured, nothing is accepted.
 */
function isAuthorized(
  request,
  env
) {
  const expected =
    (env.APP_KEY || "")
      .trim();

  const provided =
    (
      request.headers.get(
        "x-tasan-key"
      ) || ""
    ).trim();

  if (
    !expected
    || expected.length
      !== provided.length
  ) {
    return false;
  }

  let diff = 0;

  for (
    let i = 0;
    i < expected.length;
    i++
  ) {
    diff |=
      expected.charCodeAt(i)
      ^ provided.charCodeAt(i);
  }

  return diff === 0;
}

export default {
  async fetch(request, env) {
    const url =
      new URL(request.url);

    // MARK: - Health

    if (
      url.pathname === "/health"
    ) {
      return Response.json({
        ok: true,

        worker:
          "tasan-ai",

        workerVersion:
          WORKER_VERSION,

        promptVersion:
          PROMPT_VERSION,

        supportsMultipleEvents:
          true,

        maximumEventCandidates:
          MAX_EVENTS,
      });
    }

    // MARK: - Route

    if (
      url.pathname
        !== "/extract-event"
    ) {
      return new Response(
        "Not Found",
        {
          status: 404,
        }
      );
    }

    if (
      request.method
        !== "POST"
    ) {
      return new Response(
        "Method Not Allowed",
        {
          status: 405,
        }
      );
    }

    // MARK: - Authorization

    if (
      !isAuthorized(
        request,
        env
      )
    ) {
      return Response.json(
        {
          error:
            "Unauthorized",
        },
        {
          status: 401,
        }
      );
    }

    // MARK: - Request body

    const declaredLength =
      Number(
        request.headers.get(
          "content-length"
        ) || 0
      );

    if (
      declaredLength
        > MAX_BODY_BYTES
    ) {
      return Response.json(
        {
          error:
            "Request too large",
        },
        {
          status: 413,
        }
      );
    }

    const rawBody =
      await request.text();

    if (
      rawBody.length
        > MAX_BODY_BYTES
    ) {
      return Response.json(
        {
          error:
            "Request too large",
        },
        {
          status: 413,
        }
      );
    }

    let body;

    try {
      body =
        JSON.parse(
          rawBody
        );

    } catch {
      return Response.json(
        {
          error:
            "Invalid JSON body",
        },
        {
          status: 400,
        }
      );
    }

    const ocrText =
      typeof body?.ocrText
        === "string"
        ? body.ocrText.trim()
        : "";

    let deviceContext;

    try {
      deviceContext =
        normalizeDeviceContext(
          body?.deviceContext
        );

    } catch (error) {
      return Response.json(
        {
          error:
            error?.message
            ?? "Invalid deviceContext",
        },
        {
          status: 400,
        }
      );
    }

    if (!ocrText) {
      return Response.json(
        {
          error:
            "Missing ocrText",
        },
        {
          status: 400,
        }
      );
    }

    if (
      ocrText.length
        > MAX_OCR_CHARS
    ) {
      return Response.json(
        {
          error:
            "ocrText too long",
        },
        {
          status: 413,
        }
      );
    }

    // MARK: - Extraction

    try {
      const result =
        await extractEventWithClaude({
          ocrText,
          deviceContext,
          env,
        });

      const events =
        normalizeEventsResult(
          result
        );

      if (
        events.length === 0
      ) {
        throw new Error(
          "No usable event candidates returned"
        );
      }

      /*
       * Backwards compatibility:
       *
       * Existing iOS versions still read:
       *
       *   response.event
       *
       * New versions will read:
       *
       *   response.events
       *
       * Keep both temporarily.
       */
      return Response.json({
        ok: true,

        workerVersion:
          WORKER_VERSION,

        promptVersion:
          PROMPT_VERSION,

        model:
          env.CLAUDE_MODEL
          ?? null,

        event:
          events[0],

        events,
      });

    } catch (error) {
      return Response.json(
        {
          ok: false,

          workerVersion:
            WORKER_VERSION,

          promptVersion:
            PROMPT_VERSION,

          error:
            error?.message
            ?? "Unknown error",
        },
        {
          status: 500,
        }
      );
    }
  },
};

// MARK: - Result normalization

function normalizeEventsResult(
  result
) {
  /*
   * New expected mapper result:
   *
   * {
   *   events: [...]
   * }
   */
  if (
    Array.isArray(
      result?.events
    )
  ) {
    return result.events
      .slice(
        0,
        MAX_EVENTS
      );
  }

  /*
   * Transitional structure in case
   * anthropic.js wraps mapper output:
   *
   * {
   *   event: {
   *     events: [...]
   *   }
   * }
   */
  if (
    Array.isArray(
      result?.event?.events
    )
  ) {
    return result.event.events
      .slice(
        0,
        MAX_EVENTS
      );
  }

  /*
   * Old single-event structure.
   *
   * This keeps the Worker compatible
   * while the backend files are being
   * migrated one at a time.
   */
  if (
    result
    && typeof result === "object"
    && !Array.isArray(result)
  ) {
    return [
      result,
    ];
  }

  return [];
}