# Outlook Calendar Mappings

## How Mappings Are Learned

This file is auto-populated as Claude discovers calendar→project associations:

1. **From people-context**: When attendees match known client/team members
2. **From subject matching**: When calendar subjects match project-mappings terms
3. **From user confirmation**: When Claude asks and user confirms an association

## Calendar Subject → Intervals Project

| Calendar Subject Pattern | Intervals Project | Work Type |
|--------------------------|-------------------|-----------|
<!-- Claude adds mappings here as they are discovered -->

## Recurring Meeting Patterns

| Meeting Name | Intervals Project | Work Type |
|-------------|-------------------|-----------|
<!-- Claude adds recurring meeting mappings here -->

## Attendee-Based Project Inference

When a calendar event doesn't match by subject, Claude can infer the project
from the attendees list using `people-context.md`. Priority order:

1. **Exact subject match** in the table above
2. **Subject keyword match** against `project-mappings.md` terms
3. **Attendee match** against `people-context.md` associations
4. **Organizer match** against `people-context.md`

## Duration Accuracy Rules

Calendar events provide exact meeting durations. Use these to validate notes:

| Scenario | Action |
|----------|--------|
| Notes say "meeting 1h", calendar shows 1h | Confirmed - use 1h |
| Notes say "meeting 1h", calendar shows 1.5h | Flag discrepancy - suggest 1.5h |
| Notes say "meeting", no duration | Use calendar duration |
| Calendar shows 30min, notes say 2h | Meeting may have extended, or includes prep - keep notes |
| Calendar shows all-day event | Ignore for duration (it's a reminder, not a meeting) |
| Event has strikethrough/dimmed text | Skip - user declined, didn't attend |

## Description Enhancement from Calendar

When enhancing time entry descriptions with calendar context:

- Use the meeting subject as the primary description
- Add key attendee names for context (especially client names)
- Include meeting body/agenda if it adds useful detail
- For recurring meetings, include distinguishing details from this instance

Examples:
```
Calendar: "Technomic-EXSQ Weekly Touchbase" with Russell, Bhrugen
→ "Weekly touchbase with Technomic (Russell, Bhrugen) - Q1 roadmap review"

Calendar: "EWG Sprint Review" with Joy Jiang, Don Schminke
→ "EWG sprint review with Joy and Don - demo of search filters feature"

Calendar: "1:1 with Chris" body mentions "AI upskill progress"
→ "1:1 with Chris - AI upskill progress review and next steps"
```

## Time Gap Analysis

Calendar events help identify how time was spent between meetings:

```
9:00-9:15   Technomic Scrum (calendar)
9:15-11:00  [gap → likely development work]
11:00-12:00 EWG Sprint Review (calendar)
12:00-1:00  [gap → likely lunch]
1:00-3:30   [gap → check GitHub commits for this period]
3:30-4:00   1:1 with Chris (calendar)
4:00-5:00   [gap → likely development or wrap-up]
```

This gap analysis helps validate that notes account for the full workday.
