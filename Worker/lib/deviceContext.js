const MAX_CONTEXT_STRING_LENGTH = 80;

const ALLOWED_MEASUREMENT_SYSTEMS =
  new Set(["metric", "us", "uk"]);

const REFERENCE_DATE_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:?\d{2})$/i;

export function normalizeDeviceContext(
  input
) {
  if (!isPlainObject(input)) {
    throw new DeviceContextValidationError(
      "deviceContext must be an object"
    );
  }

  const locale =
    requiredString(
      input.locale,
      "locale"
    );

  const timeZoneIdentifier =
    requiredString(
      input.timeZoneIdentifier,
      "timeZoneIdentifier"
    );

  const calendarIdentifier =
    requiredString(
      input.calendarIdentifier,
      "calendarIdentifier"
    );

  const preferredLanguage =
    requiredString(
      input.preferredLanguage,
      "preferredLanguage"
    );

  const measurementSystem =
    requiredString(
      input.measurementSystem,
      "measurementSystem"
    ).toLowerCase();

  if (
    typeof input.uses24HourClock
      !== "boolean"
  ) {
    throw new DeviceContextValidationError(
      "uses24HourClock must be a boolean"
    );
  }

  if (
    !isValidTimeZone(
      timeZoneIdentifier
    )
  ) {
    throw new DeviceContextValidationError(
      "Invalid timeZoneIdentifier"
    );
  }

  if (
    !ALLOWED_MEASUREMENT_SYSTEMS
      .has(measurementSystem)
  ) {
    throw new DeviceContextValidationError(
      "Invalid measurementSystem"
    );
  }

  return {
    locale,
    timeZoneIdentifier,
    uses24HourClock:
      input.uses24HourClock,
    calendarIdentifier,
    preferredLanguage,
    measurementSystem,
    referenceDate:
      normalizeReferenceDate(
        input.referenceDate
      ),
  };
}

export class DeviceContextValidationError
  extends Error
{
  constructor(message) {
    super(message);

    this.name =
      "DeviceContextValidationError";

    this.code =
      "invalid_device_context";
  }
}

export function isValidTimeZone(
  identifier
) {
  if (
    typeof identifier !== "string"
    || !identifier.trim()
  ) {
    return false;
  }

  try {
    new Intl.DateTimeFormat(
      "en-US",
      {
        timeZone:
          identifier.trim(),
      }
    ).format(new Date());

    return true;
  } catch {
    return false;
  }
}

function normalizeReferenceDate(
  value
) {
  if (
    value === undefined
    || value === null
    || value === ""
  ) {
    return new Date().toISOString();
  }

  if (typeof value !== "string") {
    throw new DeviceContextValidationError(
      "referenceDate must be a string"
    );
  }

  const trimmed = value.trim();

  if (
    !REFERENCE_DATE_PATTERN.test(
      trimmed
    )
  ) {
    throw new DeviceContextValidationError(
      "Invalid referenceDate"
    );
  }

  const milliseconds =
    Date.parse(trimmed);

  if (
    Number.isNaN(milliseconds)
  ) {
    throw new DeviceContextValidationError(
      "Invalid referenceDate"
    );
  }

  return new Date(
    milliseconds
  ).toISOString();
}

function requiredString(
  value,
  fieldName
) {
  if (
    typeof value !== "string"
  ) {
    throw new DeviceContextValidationError(
      `${fieldName} must be a string`
    );
  }

  const trimmed = value.trim();

  if (!trimmed) {
    throw new DeviceContextValidationError(
      `${fieldName} is required`
    );
  }

  if (
    trimmed.length
      > MAX_CONTEXT_STRING_LENGTH
  ) {
    throw new DeviceContextValidationError(
      `${fieldName} is too long`
    );
  }

  return trimmed;
}

function isPlainObject(value) {
  return (
    value !== null
    && typeof value === "object"
    && !Array.isArray(value)
  );
}