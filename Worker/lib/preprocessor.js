export function preprocessOcrText(ocrText) {
  const text = String(ocrText || "");
  const lines = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  const dates = [];
  const times = [];
  const urls = [];
  const emails = [];
  const meetingLinks = [];
  const lineBuckets = {
    event: [],
    meeting: [],
    travel: [],
    hotel: [],
    reservation: [],
    document_meta: [],
    other: [],
  };

  for (const line of lines) {
    const lower = line.toLowerCase();
    const label = classifyLine(lower);

    lineBuckets[label].push(line);

    for (const match of line.matchAll(/\b(\d{4}-\d{2}-\d{2})\b/g)) {
      dates.push({ value: match[1], label, line });
    }

    for (const match of line.matchAll(/\b(\d{1,2})\.(\d{1,2})\.(\d{4})\b/g)) {
      dates.push({
        value: `${match[3]}-${match[2].padStart(2, "0")}-${match[1].padStart(2, "0")}`,
        label,
        line,
      });
    }

    for (const match of line.matchAll(/\b([01]?\d|2[0-3])[:.][0-5]\d\b/g)) {
      const hour = match[1].padStart(2, "0");
      const minute = match[0].slice(-2);
      times.push({
        value: `${hour}:${minute}`,
        label,
        line,
      });
    }

    for (const match of line.matchAll(/\bhttps?:\/\/[^\s<>()]+/gi)) {
      urls.push(match[0]);
    }

    for (const match of line.matchAll(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi)) {
      emails.push(match[0]);
    }

    for (const match of line.matchAll(
      /\b(?:meet\.google\.com\/[^\s<>()]+|teams\.microsoft\.com\/[^\s<>()]+|zoom\.us\/[^\s<>()]+)\b/gi
    )) {
      meetingLinks.push(match[0]);
    }
  }

  return {
    dates,
    times,
    urls: [...new Set(urls)],
    emails: [...new Set(emails)],
    meetingLinks: [...new Set(meetingLinks)],
    linesByType: lineBuckets,
    topLines: lines.slice(0, 12),
  };
}

function classifyLine(lower) {
  if (
    /(email sent|sent on|booking date|purchase date|payment date|issue date|created on|document created|invoice date)/.test(
      lower
    )
  ) {
    return "document_meta";
  }

  if (
    /(meet\.google\.com|teams\.microsoft\.com|zoom\.us|google meet|microsoft teams|zoom|webinar|meeting|call)/.test(
      lower
    )
  ) {
    return "meeting";
  }

  if (/(departure|boarding|arrival|flight|gate|airline|airport)/.test(lower)) {
    return "travel";
  }

  if (/(check[- ]?in|check[- ]?out|hotel|booking\.com|reservation|room|stay)/.test(lower)) {
    return "hotel";
  }

  if (/(reservation|booked|table for|dinner|restaurant)/.test(lower)) {
    return "reservation";
  }

  if (/(event|seminar|lecture|talk|speaker|conference|webinar)/.test(lower)) {
    return "event";
  }

  return "other";
}