// FreshBooks Fill Entry Script (v2 - Reliable)
// Run via: chrome-devtools evaluate_script
// Creates one row in FreshBooks week view and fills hours
//
// This script uses the "batch-set" approach which reliably fills all hours
// without values resetting on blur.

async () => {
  // ============================================================
  // CONFIGURATION - Claude fills this from mapped entry
  // ============================================================

  const ENTRY = {
    project: "Technomic",         // FreshBooks project name to search
    service: "Development",       // FreshBooks service name
    // Hours per day - FreshBooks uses Sun-Sat order (indices 0-6)
    hours: { sun: 0, mon: 7.5, tue: 4.5, wed: 4.5, thu: 0, fri: 4.5, sat: 0 }
  };

  // ============================================================
  // HELPER FUNCTIONS
  // ============================================================

  const sleep = ms => new Promise(r => setTimeout(r, ms));

  const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
    window.HTMLInputElement.prototype, 'value'
  ).set;

  function setInputValue(input, value) {
    nativeInputValueSetter.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  }

  // ============================================================
  // STEP 1: Click "New Row" button
  // ============================================================

  async function clickNewRow() {
    const buttons = document.querySelectorAll('button');
    for (const btn of buttons) {
      if (btn.textContent.includes('New Row')) {
        btn.click();
        await sleep(400);
        return { success: true };
      }
    }
    return { success: false, error: 'New Row button not found' };
  }

  // ============================================================
  // STEP 2: Type project and select from dropdown
  // ============================================================

  async function selectProject(projectName) {
    const input = document.querySelector('input[aria-label="Add a client or project"]');
    if (!input) return { success: false, error: 'Project input not found' };

    input.focus();
    setInputValue(input, projectName);
    await sleep(600);

    // Find and click the dropdown option
    const listbox = document.querySelector('[role="listbox"]');
    if (!listbox) {
      return { success: false, error: 'Dropdown not found - project may not exist' };
    }

    const options = listbox.querySelectorAll('[role="option"]');
    for (const opt of options) {
      // Skip "Loading..." option
      if (opt.textContent.includes('Loading')) continue;
      // Click the first matching option
      if (opt.textContent.toLowerCase().includes(projectName.toLowerCase())) {
        opt.click();
        await sleep(400);
        return { success: true };
      }
    }

    return { success: false, error: `No option found for "${projectName}"` };
  }

  // ============================================================
  // STEP 3: Type service
  // ============================================================

  async function fillService(serviceName) {
    const input = document.querySelector('input[aria-label="Add a service"]');
    if (!input) return { success: false, error: 'Service input not found' };

    input.focus();
    setInputValue(input, serviceName);
    await sleep(300);

    return { success: true };
  }

  // ============================================================
  // STEP 4: Click "Save row" button
  // ============================================================

  async function clickSaveRow() {
    const buttons = document.querySelectorAll('button');
    for (const btn of buttons) {
      if (btn.textContent.toLowerCase().includes('save row')) {
        btn.click();
        await sleep(500);
        return { success: true };
      }
    }
    return { success: false, error: 'Save row button not found' };
  }

  // ============================================================
  // STEP 5: Fill hours using batch-set approach (RELIABLE)
  // ============================================================

  async function fillHours(hours) {
    // Get the last 7 Duration inputs (the new row)
    const allInputs = document.querySelectorAll('input[aria-label="Duration"]:not([disabled])');
    const inputs = Array.from(allInputs).slice(-7);

    if (inputs.length < 7) {
      return { success: false, error: `Only found ${inputs.length} duration inputs` };
    }

    const dayOrder = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

    // BATCH SET: Set all values WITHOUT focus/blur between them
    for (let i = 0; i < 7; i++) {
      const day = dayOrder[i];
      const value = hours[day] || 0;
      if (value > 0) {
        setInputValue(inputs[i], value.toString());
      }
    }

    await sleep(200);

    // Dispatch change events on all inputs with values
    for (let i = 0; i < 7; i++) {
      const day = dayOrder[i];
      if (hours[day] > 0) {
        inputs[i].dispatchEvent(new Event('change', { bubbles: true }));
      }
    }

    await sleep(200);

    // Blur by clicking elsewhere
    document.body.click();
    await sleep(300);

    // Verify values
    const results = dayOrder.map((day, i) => ({
      day,
      expected: hours[day] || 0,
      actual: inputs[i].value
    }));

    return { success: true, results };
  }

  // ============================================================
  // MAIN EXECUTION
  // ============================================================

  try {
    const result = {
      project: ENTRY.project,
      service: ENTRY.service,
      steps: []
    };

    // Step 1: Click New Row
    const newRowResult = await clickNewRow();
    result.steps.push({ step: 'clickNewRow', ...newRowResult });
    if (!newRowResult.success) return { success: false, ...result };

    // Step 2: Select project
    const projectResult = await selectProject(ENTRY.project);
    result.steps.push({ step: 'selectProject', ...projectResult });
    if (!projectResult.success) return { success: false, ...result };

    // Step 3: Fill service
    const serviceResult = await fillService(ENTRY.service);
    result.steps.push({ step: 'fillService', ...serviceResult });
    if (!serviceResult.success) return { success: false, ...result };

    // Step 4: Save the row
    const saveResult = await clickSaveRow();
    result.steps.push({ step: 'saveRow', ...saveResult });
    if (!saveResult.success) return { success: false, ...result };

    // Step 5: Fill hours (batch-set approach)
    const hoursResult = await fillHours(ENTRY.hours);
    result.steps.push({ step: 'fillHours', ...hoursResult });

    // Calculate total
    const totalHours = Object.values(ENTRY.hours).reduce((a, b) => a + b, 0);

    result.success = true;
    result.totalHours = totalHours;
    result.message = `Created ${ENTRY.project}/${ENTRY.service} with ${totalHours}h`;

    return result;

  } catch (error) {
    return {
      success: false,
      error: error.message,
      stack: error.stack
    };
  }
}
