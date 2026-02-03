// Intervals Read Summary Table Script
// Run via: chrome-devtools evaluate_script
// Reads the weekly summary table and returns structured data

async () => {
  // Find all rows in the summary table
  const clientProjectCells = document.querySelectorAll('td.col-timesheet-clientproject');
  const entries = [];

  clientProjectCells.forEach(cell => {
    // Get the parent row
    const row = cell.closest('tr');
    if (!row) return;

    // Extract client and project from the cell
    // The cell contains "Client\nProject" with a newline separator
    const cellText = cell.textContent.trim();
    const parts = cellText.split('\n').map(s => s.trim()).filter(s => s);

    const client = parts[0] || '';
    const project = parts[1] || parts[0] || '';

    // Get all cells in the row
    const allCells = row.querySelectorAll('td');
    const cellTexts = Array.from(allCells).map(td => td.textContent.trim());

    // Structure: ClientProject | Billable | Mon | Tue | Wed | Thu | Fri | Sat | Sun | Total
    const billable = cellTexts[1] === 'Yes';

    const hours = {
      mon: parseFloat(cellTexts[2]) || 0,
      tue: parseFloat(cellTexts[3]) || 0,
      wed: parseFloat(cellTexts[4]) || 0,
      thu: parseFloat(cellTexts[5]) || 0,
      fri: parseFloat(cellTexts[6]) || 0,
      sat: parseFloat(cellTexts[7]) || 0,
      sun: parseFloat(cellTexts[8]) || 0
    };

    const total = parseFloat(cellTexts[9]) || 0;

    // Only include rows with hours
    if (total > 0) {
      entries.push({
        client,
        project,
        billable,
        hours,
        totalHours: total
      });
    }
  });

  // Get week info from page
  const title = document.title || '';
  const weekMatch = title.match(/Week of (\w+ \d+, \d+)/);
  const weekText = weekMatch ? weekMatch[1] : '';

  return {
    success: true,
    week: weekText,
    entries: entries,
    totalEntries: entries.length,
    grandTotal: entries.reduce((sum, e) => sum + e.totalHours, 0)
  };
}
