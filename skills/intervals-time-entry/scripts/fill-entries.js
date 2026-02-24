// Intervals Fill Entries Script
// Run via: chrome-devtools evaluate_script
// Configure DAY_INDEX and ENTRIES before running

async () => {
  // ============================================================
  // CONFIGURATION - Claude fills this from validated entries
  // ============================================================
  
  // Day index from dayIndexMap: Sun=0, Mon=1, Tue=2, Wed=3, Thu=4, Fri=5, Sat=6
  const DAY_INDEX = 2;
  
  // Validated entries - use exact project/workType names from dropdowns
  // Optional "module" field: use exact module name, or omit to auto-select "No Module" if dropdown exists
  const ENTRIES = [
    { project: "Ignite Application Development & Support", workType: "Meeting: Client Meeting - US", hours: "1", description: "Example entry" },
    // Add more entries...
  ];

  // ============================================================
  // AUTOMATION FUNCTIONS - Do not modify
  // ============================================================
  
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const results = [];

  async function selectDropdown(row, colClass, optionTitle) {
    const cell = row.querySelector(`.${colClass}`);
    if (!cell) return false;
    
    const header = cell.querySelector('.dropt-header');
    if (header) header.click();
    await sleep(300);
    
    const searchInput = cell.querySelector('.dropt-search input');
    if (searchInput) {
      searchInput.value = optionTitle.substring(0, 30);
      searchInput.dispatchEvent(new Event('input', { bubbles: true }));
      await sleep(300);
    }
    
    // Try exact match
    const option = cell.querySelector(`li[title="${optionTitle}"]`);
    if (option) {
      option.click();
      await sleep(200);
      return true;
    }
    
    // Fallback: partial match
    const allOptions = cell.querySelectorAll('li[title]');
    for (const opt of allOptions) {
      const title = opt.getAttribute('title');
      if (title && title.toLowerCase().includes(optionTitle.toLowerCase().substring(0, 20))) {
        opt.click();
        await sleep(200);
        return true;
      }
    }
    
    document.body.click();
    await sleep(100);
    return false;
  }

  async function addRow() {
    const btn = document.querySelector('button[data-add-row]') ||
                Array.from(document.querySelectorAll('button')).find(b => 
                  b.textContent.includes('Add another row'));
    if (btn) {
      btn.click();
      await sleep(500);
      return true;
    }
    return false;
  }

  async function fillEntry(rowIndex, entry) {
    const row = document.querySelector(`tr[data-project-row="${rowIndex}"]`);
    if (!row) {
      results.push({ row: rowIndex, error: 'Row not found' });
      return false;
    }

    // 1. Select Project
    const projectOk = await selectDropdown(row, 'col-time-multiple-clientproject', entry.project);
    if (!projectOk) {
      results.push({ row: rowIndex, error: `Project not found: ${entry.project}` });
      return false;
    }
    await sleep(400); // Wait for module/work type dropdowns to reload

    // 1.5. Select Module (if dropdown exists)
    const moduleCell = row.querySelector('.col-time-multiple-module');
    if (moduleCell) {
      const moduleTarget = entry.module || 'No Module';
      const moduleOk = await selectDropdown(row, 'col-time-multiple-module', moduleTarget);
      if (!moduleOk) {
        results.push({ row: rowIndex, error: `Module not found: ${moduleTarget}` });
        return false;
      }
      await sleep(300);
    }

    // 2. Select Work Type
    const wtOk = await selectDropdown(row, 'col-time-multiple-worktype', entry.workType);
    if (!wtOk) {
      results.push({ row: rowIndex, error: `Work type not found: ${entry.workType}` });
      return false;
    }
    await sleep(200);

    // 3. Fill Hours (use name attribute - reliable)
    const hoursInput = document.querySelector(`input[name="f_time[${rowIndex}][dates][${DAY_INDEX}][time]"]`);
    if (!hoursInput) {
      results.push({ row: rowIndex, error: 'Hours input not found' });
      return false;
    }
    
    hoursInput.focus();
    hoursInput.click();
    await sleep(200);
    
    // Use native setter to trigger framework updates
    const nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
    nativeSetter.call(hoursInput, entry.hours);
    hoursInput.dispatchEvent(new Event('input', { bubbles: true }));
    hoursInput.dispatchEvent(new Event('change', { bubbles: true }));
    await sleep(300);

    // 4. Fill Description in popup
    const descTextarea = document.querySelector('.popup.time-meta.is-active textarea, .popup.is-active textarea');
    if (descTextarea) {
      const textareaSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
      textareaSetter.call(descTextarea, entry.description);
      descTextarea.dispatchEvent(new Event('input', { bubbles: true }));
      descTextarea.dispatchEvent(new Event('change', { bubbles: true }));
      await sleep(100);
    }

    // Close popup
    document.querySelector('th')?.click();
    await sleep(200);

    results.push({ row: rowIndex, ok: true, hours: entry.hours });
    return true;
  }

  // ============================================================
  // MAIN EXECUTION
  // ============================================================
  
  for (let i = 0; i < ENTRIES.length; i++) {
    // Add rows if needed
    let currentRows = document.querySelectorAll('tr[data-project-row]').length;
    while (i >= currentRows) {
      await addRow();
      currentRows = document.querySelectorAll('tr[data-project-row]').length;
    }
    await fillEntry(i, ENTRIES[i]);
  }

  // Calculate totals
  const totalHours = ENTRIES.reduce((sum, e) => sum + parseFloat(e.hours), 0);
  const successCount = results.filter(r => r.ok).length;
  const errors = results.filter(r => r.error);

  return {
    filled: successCount,
    total: ENTRIES.length,
    totalHours,
    errors,
    message: errors.length === 0 
      ? `Filled ${successCount} entries (${totalHours}h). Review and click Save.`
      : `Filled ${successCount}/${ENTRIES.length}. Errors: ${errors.map(e => e.error).join(', ')}`
  };
}
