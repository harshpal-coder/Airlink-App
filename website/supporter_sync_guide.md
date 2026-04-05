# 🚀 Linking your Google Form to AirLink

Follow these steps to replace the "fake" data with your real Google Form submissions.

### Step 1: Create your Google Form
1. Create a new [Google Form](https://forms.google.com).
2. Add TWO questions:
   - **Name**: (Short answer)
   - **Amount**: (Number)
3. Go to the **Settings** tab and ensure responses are collected.

### Step 2: Link to a Google Sheet
1. Click the **Responses** tab in your Google Form.
2. Click **Link to Sheets** (the green icon).
3. Create a new spreadsheet.

### Step 3: Add the Sync Script
1. In your new Google Sheet, go to **Extensions > Apps Script**.
2. Delete any existing code and **Paste the code below**:

```javascript
function doGet() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheets()[0];
  const data = sheet.getDataRange().getValues();
  
  // Skip the header row (Timestamp, Name, Amount)
  const supporters = data.slice(1).map(row => ({
    timestamp: row[0],
    name: row[1],
    amount: parseFloat(row[2])
  }));

  return ContentService.createTextOutput(JSON.stringify(supporters))
    .setMimeType(ContentService.MimeType.JSON);
}
```

### Step 4: Deploy as a Web App
1. Click **Deploy > New Deployment**.
2. Select **Web App**.
3. Description: `AirLink Supporter Sync`.
4. Execute as: **Me**.
5. Who has access: **Anyone** (This is crucial for the website to read the data).
6. Click **Deploy** and **Authorize Access**.
7. **Copy the Web App URL** (it should end in `/exec`).

### Step 5: Update the Website
1. Provide the **Web App URL** to me, and I will update the website's code to start pulling live data!
