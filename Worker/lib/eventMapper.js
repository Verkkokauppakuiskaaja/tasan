import {
  AREA_KINDS,
} from "./prompt.js";

import {
  inferNumericDateTimesFromText,
  normalizeISODateTime,
} from "./dateParser.js";

const MAX_EVENTS = 10;

const MAX_TITLE_LENGTH = 240;
const MAX_LOCATION_LENGTH = 500;
const MAX_NOTES_LENGTH = 1500;
const MAX_URL_LENGTH = 2048;


// MARK: - Public mapper

export function mapPayloadToEventDraft(
  payload,
  recognizedText,
  deviceContext
) {
  if (!isPlainObject(payload)) {
    throw new EventSchemaError(
      "Event payload must be an object"
    );
  }

  if (!Array.isArray(payload.events)) {
    throw new EventSchemaError(
      "Event payload must contain an events array"
    );
  }

  if (payload.events.length === 0) {
    throw new EventSchemaError(
      "Event payload must contain at least one event"
    );
  }

  const sourceEvents =
    payload.events.slice(
      0,
      MAX_EVENTS
    );

  /*
   * Whole-OCR deterministic fallback is safe only when
   * there is one event candidate.
   *
   * With several candidates it could accidentally assign
   * the first visible date/time to every event.
   */
  const allowTextDateFallback =
    sourceEvents.length === 1;

  const mappedEvents =
    sourceEvents
      .map((eventPayload) =>
        mapSingleEvent(
          eventPayload,
          recognizedText,
          deviceContext,
          {
            allowTextDateFallback,
          }
        )
      )
      .filter(
        (event) =>
          event !== null
      );

  const uniqueEvents =
    removeDuplicateEvents(
      mappedEvents
    );

  if (uniqueEvents.length === 0) {
    throw new EventSchemaError(
      "No usable event candidates were returned"
    );
  }

  return {
    events:
      uniqueEvents.slice(
        0,
        MAX_EVENTS
      ),
  };
}


// MARK: - Single event

function mapSingleEvent(
  payload,
  recognizedText,
  deviceContext,
  {
    allowTextDateFallback,
  }
) {
  if (!isPlainObject(payload)) {
    return null;
  }

  const title =
    cleanString(
      payload.title,
      MAX_TITLE_LENGTH
    );

  /*
   * Without a title there is no useful candidate
   * to show in the event-selection UI.
   */
  if (!title) {
    return null;
  }

  let location =
    cleanString(
      payload.location,
      MAX_LOCATION_LENGTH
    );

  const rawURL =
    cleanString(
      payload.urlString,
      MAX_URL_LENGTH
    );

  const notes =
    cleanString(
      payload.notes,
      MAX_NOTES_LENGTH
    );

  const urlString =
    normalizeURL(
      rawURL
    );

  /*
   * If Claude interpreted a generic online-meeting
   * homepage as a URL, normalizeURL() rejects it.
   *
   * In that case the meeting platform can still be
   * preserved as the event location.
   *
   * Example:
   *
   *   https://teams.microsoft.com/
   *
   * becomes:
   *
   *   location = "Microsoft Teams"
   *   urlString = null
   */
  if (
    !location
    && !urlString
  ) {
    const inferredPlatform =
      inferMeetingPlatformFromURL(
        rawURL
      );

    if (inferredPlatform) {
      location =
        inferredPlatform;
    }
  }

  const isAllDay =
    payload.isAllDay === true;

  const timeZoneResult =
    normalizeEventTimeZone(
      payload.timeZoneIdentifier,
      deviceContext?.timeZoneIdentifier
    );

  const timeZoneIdentifier =
    timeZoneResult.value;

  const startYearIsExplicit =
    payload.startYearIsExplicit === true;

  const endYearIsExplicit =
    payload.endYearIsExplicit === true;

  const startWasProvided =
    hasStringValue(
      payload.startDate
    );

  const endWasProvided =
    hasStringValue(
      payload.endDate
    );

  const startYearFlagWasProvided =
    typeof payload.startYearIsExplicit
      === "boolean";

  const endYearFlagWasProvided =
    typeof payload.endYearIsExplicit
      === "boolean";


  // MARK: - Model dates

  const modelStart =
    normalizeISODateTime(
      payload.startDate,
      timeZoneIdentifier,
      isAllDay,
      {
        yearIsExplicit:
          startYearIsExplicit,

        referenceDate:
          deviceContext?.referenceDate
          ?? null,
      }
    );

  const modelEnd =
    normalizeISODateTime(
      payload.endDate,
      timeZoneIdentifier,
      isAllDay,
      {
        yearIsExplicit:
          endYearIsExplicit,

        referenceDate:
          deviceContext?.referenceDate
          ?? null,

        minimumInstantMilliseconds:
          modelStart
            ?.instantMilliseconds
          ?? null,
      }
    );


  // MARK: - Deterministic OCR fallback

  let fallback =
    null;

  if (
    allowTextDateFallback
    && !isAllDay
    && (
      !modelStart
      || !modelEnd
    )
  ) {
    fallback =
      inferNumericDateTimesFromText(
        recognizedText,
        timeZoneIdentifier,
        deviceContext?.referenceDate
        ?? null
      );
  }

  const start =
    modelStart
    ?? fallback?.start
    ?? null;

  let end =
    modelEnd
    ?? fallback?.end
    ?? null;


  // MARK: - Validation

  let requiresUserInput =
    false;

  /*
   * Invalid timezone is uncertain even when we can
   * fall back to the device timezone.
   */
  if (
    timeZoneResult.invalid
  ) {
    requiresUserInput =
      true;
  }

  /*
   * Start is always required.
   */
  if (!start) {
    requiresUserInput =
      true;
  }

  /*
   * Timed event requires an explicit/reliably
   * resolved end time.
   *
   * Tasan! must never invent a duration.
   */
  if (
    !isAllDay
    && !end
  ) {
    requiresUserInput =
      true;
  }

  /*
   * Claude may have supplied startDate but failed
   * to provide the corresponding year-explicitness flag.
   *
   * If deterministic fallback successfully resolved
   * the date, we can still accept it.
   */
  if (
    startWasProvided
    && !startYearFlagWasProvided
    && !fallback?.start
  ) {
    requiresUserInput =
      true;
  }

  if (
    endWasProvided
    && !endYearFlagWasProvided
    && !fallback?.end
  ) {
    requiresUserInput =
      true;
  }

  /*
   * If Claude supplied a date but normalization rejected it,
   * only a successful deterministic fallback may rescue it.
   */
  if (
    startWasProvided
    && !modelStart
    && !fallback?.start
  ) {
    requiresUserInput =
      true;
  }

  if (
    endWasProvided
    && !modelEnd
    && !fallback?.end
  ) {
    requiresUserInput =
      true;
  }

  /*
   * End must be later than start.
   */
  if (
    start
    && end
    && end.instantMilliseconds
      <= start.instantMilliseconds
  ) {
    end =
      null;

    requiresUserInput =
      true;
  }


  // MARK: - Final status

  /*
   * Do not blindly preserve Claude's
   * "needs_user_input" status.
   *
   * The deterministic date parser may have resolved
   * the exact missing-year date/time after Claude's
   * initial assessment.
   *
   * Example:
   *
   *   2.10 kl. 18:30-20:00
   *
   * Claude may be conservative because the year is
   * absent, while our deterministic parser can safely
   * resolve the nearest non-past year.
   *
   * The final status therefore comes from the
   * validated and normalized result.
   */
  const finalStatus =
    requiresUserInput
      ? "needs_user_input"
      : "ready";

  return {
    status:
      finalStatus,

    title,

    startDate:
      start?.value
      ?? null,

    endDate:
      end?.value
      ?? null,

    isAllDay,

    location,

    urlString,

    notes,

    areaKind:
      AREA_KINDS.includes(
        payload.areaKind
      )
        ? payload.areaKind
        : "other",

    preparation:
      cleanString(
        payload.preparation,
        MAX_NOTES_LENGTH
      ),

    recognizedText:
      normalizeRecognizedText(
        recognizedText
      ),

    timeZoneIdentifier,
  };
}


// MARK: - Duplicate removal

function removeDuplicateEvents(
  events
) {
  const seen =
    new Set();

  const result =
    [];

  for (
    const event of events
  ) {
    const signature =
      createEventSignature(
        event
      );

    if (
      seen.has(
        signature
      )
    ) {
      continue;
    }

    seen.add(
      signature
    );

    result.push(
      event
    );
  }

  return result;
}


function createEventSignature(
  event
) {
  return [
    normalizeSignatureText(
      event.title
    ),

    event.startDate
      ?? "",

    event.endDate
      ?? "",

    event.isAllDay
      ? "all-day"
      : "timed",

    normalizeSignatureText(
      event.location
    ),
  ].join("|");
}


function normalizeSignatureText(
  value
) {
  if (
    typeof value !== "string"
  ) {
    return "";
  }

  return value
    .trim()
    .replace(
      /\s+/g,
      " "
    )
    .toLocaleLowerCase();
}


// MARK: - Time zone

function normalizeEventTimeZone(
  value,
  fallback
) {
  const fallbackCandidate =
    cleanString(
      fallback,
      100
    );

  const fallbackTimeZone =
    isValidTimeZone(
      fallbackCandidate
    )
      ? fallbackCandidate
      : "UTC";

  const candidate =
    cleanString(
      value,
      100
    );

  /*
   * No model timezone:
   * device timezone is expected and valid behavior.
   */
  if (!candidate) {
    return {
      value:
        fallbackTimeZone,

      invalid:
        false,
    };
  }

  /*
   * Claude returned something that is not
   * a valid IANA timezone.
   */
  if (
    !isValidTimeZone(
      candidate
    )
  ) {
    return {
      value:
        fallbackTimeZone,

      invalid:
        true,
    };
  }

  return {
    value:
      candidate,

    invalid:
      false,
  };
}


/*
 * Local timezone validation.
 *
 * This intentionally lives in eventMapper.js so that
 * the mapper does not depend on deviceContext.js
 * exporting a separate isValidTimeZone helper.
 */
function isValidTimeZone(
  value
) {
  if (
    typeof value !== "string"
    || !value.trim()
  ) {
    return false;
  }

  try {
    new Intl.DateTimeFormat(
      "en-US",
      {
        timeZone:
          value.trim(),
      }
    ).format(
      new Date()
    );

    return true;

  } catch {
    return false;
  }
}


// MARK: - URL

function normalizeURL(
  value
) {
  const cleaned =
    cleanString(
      value,
      MAX_URL_LENGTH
    );

  if (!cleaned) {
    return null;
  }

  const candidate =
    /^https?:\/\//i.test(
      cleaned
    )
      ? cleaned
      : `https://${cleaned}`;

  try {
    const url =
      new URL(
        candidate
      );

    if (
      url.protocol !== "https:"
      && url.protocol !== "http:"
    ) {
      return null;
    }

    /*
     * A generic service homepage is not a
     * usable meeting participation URL.
     */
    if (
      isGenericMeetingHomepage(
        url
      )
    ) {
      return null;
    }

    return url.toString();

  } catch {
    return null;
  }
}


function isGenericMeetingHomepage(
  url
) {
  const host =
    url.hostname
      .toLowerCase()
      .replace(
        /^www\./,
        ""
      );

  const normalizedPath =
    url.pathname
      .replace(
        /\/+/g,
        "/"
      );

  const isRootPath =
    normalizedPath === "/"
    || normalizedPath === "";

  if (
    host === "teams.microsoft.com"
    && isRootPath
  ) {
    return true;
  }

  if (
    host === "zoom.us"
    && isRootPath
  ) {
    return true;
  }

  if (
    host === "meet.google.com"
    && isRootPath
  ) {
    return true;
  }

  return false;
}


function inferMeetingPlatformFromURL(
  value
) {
  if (
    typeof value !== "string"
    || !value.trim()
  ) {
    return null;
  }

  const lower =
    value.toLowerCase();

  if (
    lower.includes(
      "teams.microsoft.com"
    )
  ) {
    return "Microsoft Teams";
  }

  if (
    lower.includes(
      "zoom.us"
    )
  ) {
    return "Zoom";
  }

  if (
    lower.includes(
      "meet.google.com"
    )
  ) {
    return "Google Meet";
  }

  return null;
}


// MARK: - String helpers

function cleanString(
  value,
  maximumLength
) {
  if (
    typeof value !== "string"
  ) {
    return null;
  }

  const cleaned =
    value
      .replace(
        /\s+/g,
        " "
      )
      .trim();

  if (!cleaned) {
    return null;
  }

  if (
    typeof maximumLength
      !== "number"
  ) {
    return cleaned;
  }

  return cleaned.slice(
    0,
    maximumLength
  );
}


function normalizeRecognizedText(
  value
) {
  if (
    typeof value !== "string"
  ) {
    return "";
  }

  return value.trim();
}


function hasStringValue(
  value
) {
  return (
    typeof value === "string"
    && value
      .trim()
      .length > 0
  );
}


// MARK: - Object validation

function isPlainObject(
  value
) {
  return (
    value !== null
    && typeof value === "object"
    && !Array.isArray(
      value
    )
  );
}


// MARK: - Error

export class EventSchemaError
  extends Error
{
  constructor(
    message
  ) {
    super(message);

    this.name =
      "EventSchemaError";

    this.code =
      "invalid_model_output";

    this.httpStatus =
      502;

    this.retryable =
      false;
  }
}