import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import worker from "../worker.js";

const env = {
  APP_KEY: "test-key",
  CLAUDE_API_KEY: "sk-test",
  CLAUDE_MODEL: "claude-haiku-5-5",
};

const deviceContext = {
  locale: "fi_FI",
  timeZoneIdentifier: "Europe/Helsinki",
  calendarIdentifier: "gregorian",
  preferredLanguage: "fi-FI",
  measurementSystem: "metric",
  uses24HourClock: true,
  referenceDate: "2026-10-18T09:00:00+03:00",
};

const realFetch = globalThis.fetch;
let sentBody;

afterEach(() => {
  globalThis.fetch = realFetch;
  sentBody = undefined;
});

// Stands in for api.anthropic.com and returns the given model reply.
function mockClaude(events, stopReason = "end_turn") {
  globalThis.fetch = async (url, init) => {
    assert.match(String(url), /api\.anthropic\.com\/v1\/messages/);
    sentBody = JSON.parse(init.body);
    return new Response(
      JSON.stringify({
        id: "msg_test",
        type: "message",
        role: "assistant",
        model: env.CLAUDE_MODEL,
        content: [{ type: "text", text: JSON.stringify({ events }) }],
        stop_reason: stopReason,
        usage: { input_tokens: 10, output_tokens: 10 },
      }),
      { status: 200, headers: { "content-type": "application/json" } }
    );
  };
}

function post(body, key = env.APP_KEY) {
  return worker.fetch(
    new Request("https://tasan-ai.example/extract-event", {
      method: "POST",
      headers: { "content-type": "application/json", "x-tasan-key": key },
      body: JSON.stringify(body),
    }),
    env
  );
}

test("rejects a wrong app key", async () => {
  const response = await post({ ocrText: "x", deviceContext }, "wrong");
  assert.equal(response.status, 401);
});

test("health names the Tasan worker", async () => {
  const response = await worker.fetch(new Request("https://tasan-ai.example/health"), env);
  assert.equal((await response.json()).worker, "tasan-ai");
});

test("returns the event with area and preparation", async () => {
  mockClaude([
    {
      status: "ready",
      title: "Luokkaretki Nuuksioon",
      startDate: "2026-10-23T09:00:00+03:00",
      endDate: "2026-10-23T14:00:00+03:00",
      startYearIsExplicit: false,
      endYearIsExplicit: false,
      isAllDay: false,
      location: "Nuuksio",
      urlString: null,
      notes: null,
      timeZoneIdentifier: "Europe/Helsinki",
      areaKind: "school",
      preparation: "Eväät, juomapullo ja säänmukainen vaatetus",
    },
  ]);

  const response = await post({
    ocrText: "Luokkaretki Nuuksioon pe 23.10. klo 9-14. Mukaan eväät, juomapullo ja säänmukainen vaatetus.",
    deviceContext,
  });
  const json = await response.json();

  assert.equal(response.status, 200, JSON.stringify(json));
  assert.equal(json.events.length, 1);
  assert.equal(json.events[0].title, "Luokkaretki Nuuksioon");
  assert.equal(json.events[0].areaKind, "school");
  assert.equal(json.events[0].preparation, "Eväät, juomapullo ja säänmukainen vaatetus");

  assert.equal(sentBody.model, "claude-haiku-5-5");
  assert.equal(sentBody.output_config.format.type, "json_schema");
  assert.ok(sentBody.system.includes("Tasan!"));
});

test("unknown area falls back to other", async () => {
  mockClaude([
    {
      status: "ready",
      title: "Hammaslääkäri",
      startDate: "2026-10-27T15:00:00+02:00",
      endDate: "2026-10-27T15:30:00+02:00",
      startYearIsExplicit: false,
      endYearIsExplicit: false,
      isAllDay: false,
      location: null,
      urlString: null,
      notes: null,
      timeZoneIdentifier: "Europe/Helsinki",
      areaKind: "dentist",
      preparation: null,
    },
  ]);
  const json = await (await post({ ocrText: "Hammaslääkäri ti 27.10. klo 15-15.30", deviceContext })).json();
  assert.equal(json.events[0].areaKind, "other");
  assert.equal(json.events[0].preparation, null);
});

test("a refusal is an error, not an empty event", async () => {
  mockClaude([], "refusal");
  const response = await post({ ocrText: "jotain", deviceContext });
  assert.notEqual(response.status, 200);
  assert.equal((await response.json()).ok, false);
});
