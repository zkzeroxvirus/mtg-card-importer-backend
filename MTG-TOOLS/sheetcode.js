const SHEET_NAME = "Roguelike Save Data";

function parsePostedData(e) {
  if (!e) {
    return { error: "Missing event" };
  }

  let raw = "";
  if (e.postData && typeof e.postData.contents === "string" && e.postData.contents !== "") {
    raw = e.postData.contents;
  } else if (e.parameter) {
    if (typeof e.parameter.payload === "string" && e.parameter.payload !== "") {
      raw = e.parameter.payload;
    } else if (typeof e.parameter.data === "string" && e.parameter.data !== "") {
      raw = e.parameter.data;
    } else if (Object.keys(e.parameter).length > 0) {
      return e.parameter;
    }
  }

  if (!raw) {
    return { error: "Missing postData" };
  }

  let decoded = raw;
  try {
    decoded = decodeURIComponent(raw);
  } catch (err) {
    return { error: "Decode failed", err: err.toString() };
  }

  try {
    return JSON.parse(decoded);
  } catch (err) {
    return { error: "Parse failed", err: err.toString(), raw: decoded };
  }
}

function ensureSheet() {
  const sh = SpreadsheetApp.getActive().getSheetByName(SHEET_NAME);
  if (!sh) {
    throw new Error("Sheet not found");
  }
  // Optional: add headers if missing
  if (sh.getLastRow() === 0) {
    sh.appendRow([
      "Timestamp",
      "Name",
      "Value",
      "Description",
      "PlayerKey",
      "Achievements",
      "Crypt",
      "Tickets",
      "Captures",
      "Brands"
    ]);
  }
  return sh;
}

function doPost(e) {
  try {
    const sheet = ensureSheet();

    const data = parsePostedData(e);
    if (data.error) {
      return json(data);
    }

    const playerKey = data.playerKey || "";
    if (!playerKey) {
      return json({ error: "playerKey required" });
    }

    const rows = sheet.getDataRange().getValues();
    let foundRow = -1;
    for (let i = 0; i < rows.length; i++) {
      if (rows[i][4] === playerKey) { // col 5 (index 4)
        foundRow = i + 1; // 1-based
        break;
      }
    }

    const rowValues = [
      new Date(),
      data.name || "",
      data.value,
      data.description || "",
      playerKey,
      data.achievements || "",
      data.crypt || "",
      data.tickets || "",
      data.captures || "",
      data.brands || ""
    ];

    if (foundRow > 0) {
      sheet.getRange(foundRow, 1, 1, rowValues.length).setValues([rowValues]);
    } else {
      sheet.appendRow(rowValues);
    }

    return json({ status: "OK" });
  } catch (err) {
    return json({ error: err.message || err.toString() });
  }
}

function doGet(e) {
  try {
    if (!e || !e.parameter || !e.parameter.playerKey) {
      return json({ error: "Missing playerKey" });
    }
    const playerKey = e.parameter.playerKey;
    const sheet = ensureSheet();
    const rows = sheet.getDataRange().getValues();

    for (let i = rows.length - 1; i >= 0; i--) {
      if (rows[i][4] === playerKey) { // col 5 (index 4)
        return json({
          playerKey: rows[i][4],
          name: rows[i][1],
          description: rows[i][3],
          value: rows[i][2],
          achievements: rows[i][5] || "",
          crypt: rows[i][6] || "",
          tickets: rows[i][7] || "",
          captures: rows[i][8] || "",
          brands: rows[i][9] || ""
        });
      }
    }
    return json({}); // not found → empty object (Lua handles empty)
  } catch (err) {
    return json({ error: err.message || err.toString() });
  }
}

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}