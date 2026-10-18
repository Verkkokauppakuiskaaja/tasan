import {
  isValidTimeZone,
} from "./deviceContext.js";

const DATE_ONLY_PATTERN =
  /^(\d{4})-(\d{2})-(\d{2})$/;

const LOCAL_DATE_TIME_PATTERN =
  /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,3})?)?$/;

const EXPLICIT_DATE_TIME_PATTERN =
  /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,3})?)?(Z|[+-]\d{2}:?\d{2})$/i;

const NUMERIC_DATE_TIME_RANGE_PATTERN =
  /(?:^|[^\d])(\d{1,2})\s*[.\/-]\s*(\d{1,2})(?:\s*[.\/-]\s*(\d{2,4}))?\s*(?:klo|kl\.?|at)?\s*(\d{1,2})\s*[:.]\s*(\d{2})\s*(?:-|–|—|to|till)\s*(\d{1,2})\s*[:.]\s*(\d{2})/giu;

const NUMERIC_DATE_TIME_SINGLE_PATTERN =
  /(?:^|[^\d])(\d{1,2})\s*[.\/-]\s*(\d{1,2})(?:\s*[.\/-]\s*(\d{2,4}))?\s*(?:klo|kl\.?|at)?\s*(\d{1,2})\s*[:.]\s*(\d{2})/giu;

export function normalizeISODateTime(
  value,
  timeZoneIdentifier,
  isAllDay = false,
  options = {}
) {
  if (
    value === null
    || value === undefined
    || typeof value !== "string"
  ) {
    return null;
  }

  const trimmed = value.trim();

  if (
    !trimmed
    || !isValidTimeZone(
      timeZoneIdentifier
    )
  ) {
    return null;
  }

  const parsed =
    parseDateInput(
      trimmed,
      isAllDay
    );

  if (!parsed) {
    return null;
  }

  const yearIsExplicit =
    options.yearIsExplicit !== false;

  if (yearIsExplicit) {
    return normalizeExplicitYearValue(
      parsed,
      timeZoneIdentifier
    );
  }

  return normalizeInferredYearValue(
    parsed,
    timeZoneIdentifier,
    isAllDay,
    {
      referenceDate:
        options.referenceDate,

      minimumInstantMilliseconds:
        options
          .minimumInstantMilliseconds,
    }
  );
}

export function inferNumericDateTimesFromText(
  text,
  timeZoneIdentifier,
  referenceDate
) {
  if (
    typeof text !== "string"
    || !text.trim()
    || !isValidTimeZone(
      timeZoneIdentifier
    )
  ) {
    return null;
  }

  const normalizedText =
    text
      .replace(/\u00a0/g, " ")
      .replace(/[−]/g, "-");

  const rangeMatch =
    firstMatch(
      NUMERIC_DATE_TIME_RANGE_PATTERN,
      normalizedText
    );

  if (rangeMatch) {
    return dateTimesFromNumericMatch(
      rangeMatch,
      timeZoneIdentifier,
      referenceDate,
      true
    );
  }

  const singleMatch =
    firstMatch(
      NUMERIC_DATE_TIME_SINGLE_PATTERN,
      normalizedText
    );

  if (!singleMatch) {
    return null;
  }

  return dateTimesFromNumericMatch(
    singleMatch,
    timeZoneIdentifier,
    referenceDate,
    false
  );
}

export function dateInstant(
  value
) {
  if (
    typeof value !== "string"
    || !value.trim()
  ) {
    return null;
  }

  const milliseconds =
    Date.parse(value);

  return Number.isNaN(
    milliseconds
  )
    ? null
    : milliseconds;
}

function firstMatch(
  pattern,
  text
) {
  pattern.lastIndex = 0;

  return pattern.exec(text);
}

function dateTimesFromNumericMatch(
  match,
  timeZoneIdentifier,
  referenceDate,
  hasEndTime
) {
  const day =
    Number(match[1]);

  const month =
    Number(match[2]);

  const explicitYear =
    normalizeSourceYear(
      match[3]
    );

  const startHour =
    Number(match[4]);

  const startMinute =
    Number(match[5]);

  if (
    !isClockTimeValid(
      startHour,
      startMinute
    )
    || !isMonthDayPlausible(
      month,
      day
    )
  ) {
    return null;
  }

  const placeholderYear =
    explicitYear ?? 2000;

  const startInput =
    localDateTimeString(
      placeholderYear,
      month,
      day,
      startHour,
      startMinute
    );

  const start =
    normalizeISODateTime(
      startInput,
      timeZoneIdentifier,
      false,
      {
        yearIsExplicit:
          explicitYear !== null,

        referenceDate,
      }
    );

  if (!start) {
    return null;
  }

  if (!hasEndTime) {
    return {
      start,
      end: null,
      source:
        "numeric_date_time",
    };
  }

  const endHour =
    Number(match[6]);

  const endMinute =
    Number(match[7]);

  if (
    !isClockTimeValid(
      endHour,
      endMinute
    )
  ) {
    return {
      start,
      end: null,
      source:
        "numeric_date_time",
    };
  }

  const startLocal =
    componentsInTimeZone(
      new Date(
        start.instantMilliseconds
      ),
      timeZoneIdentifier
    );

  let endComponents = {
    year:
      startLocal.year,

    month:
      startLocal.month,

    day:
      startLocal.day,

    hour:
      endHour,

    minute:
      endMinute,

    second: 0,
  };

  if (
    endHour < startHour
    || (
      endHour === startHour
      && endMinute <= startMinute
    )
  ) {
    endComponents =
      addLocalDays(
        endComponents,
        1
      );
  }

  const end =
    localComponentsToNormalizedValue(
      endComponents,
      timeZoneIdentifier
    );

  return {
    start,
    end,
    source:
      "numeric_date_time_range",
  };
}

function normalizeSourceYear(
  value
) {
  if (
    value === undefined
    || value === null
    || value === ""
  ) {
    return null;
  }

  const numeric =
    Number(value);

  if (
    !Number.isInteger(
      numeric
    )
  ) {
    return null;
  }

  if (
    numeric >= 1000
    && numeric <= 9999
  ) {
    return numeric;
  }

  if (
    numeric >= 0
    && numeric <= 99
  ) {
    return 2000 + numeric;
  }

  return null;
}

function isClockTimeValid(
  hour,
  minute
) {
  return (
    Number.isInteger(hour)
    && Number.isInteger(minute)
    && hour >= 0
    && hour <= 23
    && minute >= 0
    && minute <= 59
  );
}

function isMonthDayPlausible(
  month,
  day
) {
  if (
    !Number.isInteger(month)
    || !Number.isInteger(day)
    || month < 1
    || month > 12
    || day < 1
    || day > 31
  ) {
    return false;
  }

  const validationYear = 2000;

  const validationDate =
    new Date(
      Date.UTC(
        validationYear,
        month - 1,
        day
      )
    );

  return (
    validationDate
      .getUTCMonth() + 1
      === month

    && validationDate
      .getUTCDate()
      === day
  );
}

function localDateTimeString(
  year,
  month,
  day,
  hour,
  minute
) {
  return (
    `${pad4(year)}-`
    + `${pad2(month)}-`
    + `${pad2(day)}T`
    + `${pad2(hour)}:`
    + `${pad2(minute)}:00`
  );
}

function pad2(
  value
) {
  return String(value)
    .padStart(2, "0");
}

function pad4(
  value
) {
  return String(value)
    .padStart(4, "0");
}

function addLocalDays(
  components,
  days
) {
  const date =
    new Date(
      Date.UTC(
        components.year,
        components.month - 1,
        components.day + days,
        components.hour,
        components.minute,
        components.second
      )
    );

  return {
    year:
      date.getUTCFullYear(),

    month:
      date.getUTCMonth() + 1,

    day:
      date.getUTCDate(),

    hour:
      date.getUTCHours(),

    minute:
      date.getUTCMinutes(),

    second:
      date.getUTCSeconds(),
  };
}

function parseDateInput(
  value,
  isAllDay
) {
  const explicitMatch =
    value.match(
      EXPLICIT_DATE_TIME_PATTERN
    );

  if (explicitMatch) {
    const components =
      componentsFromMatch(
        explicitMatch
      );

    return areValidComponents(
      components
    )
      ? {
          components,
          originalValue:
            value,
          hasExplicitOffset:
            true,
        }
      : null;
  }

  const dateOnlyMatch =
    value.match(
      DATE_ONLY_PATTERN
    );

  if (dateOnlyMatch) {
    if (!isAllDay) {
      return null;
    }

    const components = {
      year:
        Number(
          dateOnlyMatch[1]
        ),

      month:
        Number(
          dateOnlyMatch[2]
        ),

      day:
        Number(
          dateOnlyMatch[3]
        ),

      hour: 0,
      minute: 0,
      second: 0,
    };

    return areValidComponents(
      components
    )
      ? {
          components,
          originalValue:
            value,
          hasExplicitOffset:
            false,
        }
      : null;
  }

  const localDateTimeMatch =
    value.match(
      LOCAL_DATE_TIME_PATTERN
    );

  if (!localDateTimeMatch) {
    return null;
  }

  const components =
    componentsFromMatch(
      localDateTimeMatch
    );

  return areValidComponents(
    components
  )
    ? {
        components,
        originalValue:
          value,
        hasExplicitOffset:
          false,
      }
    : null;
}

function normalizeExplicitYearValue(
  parsed,
  timeZoneIdentifier
) {
  if (
    parsed.hasExplicitOffset
  ) {
    const milliseconds =
      Date.parse(
        parsed.originalValue
      );

    if (
      Number.isNaN(
        milliseconds
      )
    ) {
      return null;
    }

    return {
      value:
        new Date(
          milliseconds
        ).toISOString(),

      instantMilliseconds:
        milliseconds,
    };
  }

  return localComponentsToNormalizedValue(
    parsed.components,
    timeZoneIdentifier
  );
}

function normalizeInferredYearValue(
  parsed,
  timeZoneIdentifier,
  isAllDay,
  {
    referenceDate,
    minimumInstantMilliseconds,
  }
) {
  const referenceMilliseconds =
    parseReferenceMilliseconds(
      referenceDate
    );

  if (
    referenceMilliseconds === null
  ) {
    return null;
  }

  const anchorMilliseconds =
    Number.isFinite(
      minimumInstantMilliseconds
    )
      ? minimumInstantMilliseconds
      : referenceMilliseconds;

  const anchorLocal =
    componentsInTimeZone(
      new Date(
        anchorMilliseconds
      ),
      timeZoneIdentifier
    );

  for (
    let yearOffset = 0;
    yearOffset <= 8;
    yearOffset += 1
  ) {
    const components = {
      ...parsed.components,
      year:
        anchorLocal.year
        + yearOffset,
    };

    const normalized =
      localComponentsToNormalizedValue(
        components,
        timeZoneIdentifier
      );

    if (!normalized) {
      continue;
    }

    if (isAllDay) {
      if (
        compareLocalDates(
          components,
          anchorLocal
        ) >= 0
      ) {
        return normalized;
      }

      continue;
    }

    if (
      normalized
        .instantMilliseconds
      >= anchorMilliseconds
    ) {
      return normalized;
    }

    if (
      yearOffset === 0
      && components.month
        === anchorLocal.month
      && components.day
        === anchorLocal.day
    ) {
      return null;
    }
  }

  return null;
}

function parseReferenceMilliseconds(
  value
) {
  if (
    typeof value !== "string"
    || !value.trim()
  ) {
    return null;
  }

  const milliseconds =
    Date.parse(value);

  return Number.isNaN(
    milliseconds
  )
    ? null
    : milliseconds;
}

function componentsFromMatch(
  match
) {
  return {
    year:
      Number(match[1]),

    month:
      Number(match[2]),

    day:
      Number(match[3]),

    hour:
      Number(match[4]),

    minute:
      Number(match[5]),

    second:
      Number(
        match[6] || "0"
      ),
  };
}

function localComponentsToNormalizedValue(
  components,
  timeZoneIdentifier
) {
  if (
    !areValidComponents(
      components
    )
    || !isValidTimeZone(
      timeZoneIdentifier
    )
  ) {
    return null;
  }

  const requestedUtc =
    Date.UTC(
      components.year,
      components.month - 1,
      components.day,
      components.hour,
      components.minute,
      components.second
    );

  let candidate =
    requestedUtc;

  for (
    let index = 0;
    index < 4;
    index += 1
  ) {
    const offset =
      getTimeZoneOffsetMilliseconds(
        timeZoneIdentifier,
        new Date(candidate)
      );

    const adjusted =
      requestedUtc - offset;

    if (
      adjusted === candidate
    ) {
      break;
    }

    candidate =
      adjusted;
  }

  const roundTrip =
    componentsInTimeZone(
      new Date(candidate),
      timeZoneIdentifier
    );

  if (
    !sameComponents(
      roundTrip,
      components
    )
  ) {
    return null;
  }

  return {
    value:
      new Date(
        candidate
      ).toISOString(),

    instantMilliseconds:
      candidate,
  };
}

function areValidComponents(
  components
) {
  if (
    !Number.isInteger(
      components.year
    )
    || !Number.isInteger(
      components.month
    )
    || !Number.isInteger(
      components.day
    )
    || !Number.isInteger(
      components.hour
    )
    || !Number.isInteger(
      components.minute
    )
    || !Number.isInteger(
      components.second
    )
  ) {
    return false;
  }

  if (
    components.month < 1
    || components.month > 12
    || components.day < 1
    || components.day > 31
    || components.hour < 0
    || components.hour > 23
    || components.minute < 0
    || components.minute > 59
    || components.second < 0
    || components.second > 59
  ) {
    return false;
  }

  const validationDate =
    new Date(
      Date.UTC(
        components.year,
        components.month - 1,
        components.day
      )
    );

  return (
    validationDate
      .getUTCFullYear()
      === components.year

    && validationDate
      .getUTCMonth() + 1
      === components.month

    && validationDate
      .getUTCDate()
      === components.day
  );
}

function compareLocalDates(
  first,
  second
) {
  const firstValue =
    first.year * 10_000
    + first.month * 100
    + first.day;

  const secondValue =
    second.year * 10_000
    + second.month * 100
    + second.day;

  return Math.sign(
    firstValue - secondValue
  );
}

function getTimeZoneOffsetMilliseconds(
  timeZoneIdentifier,
  date
) {
  const components =
    componentsInTimeZone(
      date,
      timeZoneIdentifier
    );

  const representedAsUtc =
    Date.UTC(
      components.year,
      components.month - 1,
      components.day,
      components.hour,
      components.minute,
      components.second
    );

  return (
    representedAsUtc
    - date.getTime()
  );
}

function componentsInTimeZone(
  date,
  timeZoneIdentifier
) {
  const formatter =
    new Intl.DateTimeFormat(
      "en-CA",
      {
        timeZone:
          timeZoneIdentifier,

        hour12: false,
        hourCycle: "h23",

        year: "numeric",
        month: "2-digit",
        day: "2-digit",

        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
      }
    );

  const values = {};

  for (
    const part
    of formatter
      .formatToParts(date)
  ) {
    if (
      part.type !== "literal"
    ) {
      values[part.type] =
        part.value;
    }
  }

  return {
    year:
      Number(values.year),

    month:
      Number(values.month),

    day:
      Number(values.day),

    hour:
      Number(values.hour),

    minute:
      Number(values.minute),

    second:
      Number(values.second),
  };
}

function sameComponents(
  first,
  second
) {
  return (
    first.year
      === second.year

    && first.month
      === second.month

    && first.day
      === second.day

    && first.hour
      === second.hour

    && first.minute
      === second.minute

    && first.second
      === second.second
  );
}