# ZZedc v1.1 User Training Guide

## Complete Quick-Start Guides for All Features

Welcome to ZZedc v1.1! This guide walks you through using each new feature step-by-step. No technical experience required.

---

## Table of Contents

1. [Feature #1: Pre-Built Instruments Library](#feature-1-pre-built-instruments-library)
2. [Feature #2: Enhanced Field Types](#feature-2-enhanced-field-types)
3. [Feature #3: Quality Dashboard](#feature-3-quality-dashboard)
4. [Feature #4: Form Branching Logic](#feature-4-form-branching-logic)
5. [Feature #5: Multi-Format Export](#feature-5-multi-format-export)

---

## Feature #1: Pre-Built Instruments Library

### What Is It?

The Instruments Library gives you ready-to-use, validated survey forms that researchers have already tested and refined. Instead of creating forms from scratch, you can import pre-made instruments in one click.

### Available Instruments

| Instrument | Code | Items | Purpose |
|-----------|------|-------|---------|
| **PHQ-9** | PHQ-9 | 9 | Depression screening (9-question) |
| **GAD-7** | GAD-7 | 7 | Anxiety screening (7-question) |
| **DASS-21** | DASS-21 | 21 | Stress/Anxiety/Depression (21-question) |
| **SF-36** | SF-36 | 28 | Quality of life (36-question) |
| **AUDIT-C** | AUDIT-C | 3 | Alcohol use screening (3-question) |
| **STOP-BANG** | STOP-BANG | 8 | Sleep apnea screening (8-question) |

### How to Import an Instrument

**Step 1: Go to Home Tab**
- Open ZZedc
- Click on the **Home** tab at the top

**Step 2: Find Instrument Import**
- Look for the "Instrument Import" section
- You'll see a list of available instruments

**Step 3: Select Your Instrument**
- Click on the instrument you want to use (e.g., "PHQ-9")
- You'll see a preview of what the form looks like

**Step 4: Configure (Optional)**
- Give your form a name (e.g., "Baseline PHQ-9")
- Add a description (optional)
- Click **Import**

**That's it!** The instrument is now available in your EDC system.

### Using the Imported Instrument

Once imported, the instrument appears as a regular form:

1. In the **EDC** tab, participants see the form
2. They answer the questions
3. Results are automatically stored
4. You can export the data anytime

### Example: Importing PHQ-9 for a Depression Study

```
1. Click Home tab
2. Find "Patient Health Questionnaire (PHQ-9)" in the list
3. Click the radio button next to it
4. Click Preview to see the 9 questions
5. Click Import
6. Name it "Screening PHQ-9"
7. Click Confirm
```

**Result**: Participants now see the PHQ-9 depression screening form with all 9 questions properly formatted.

### Customizing Instruments

**Want to rename questions?**
- You can edit forms after import (requires admin access)
- Go to EDC tab → Select form → Edit

**Want to change answer options?**
- Pre-built instruments have standard answer choices
- These match published research standards
- Changing them may affect scientific validity

**Want to add more questions?**
- Import the base instrument
- Then add custom questions to the same form

### Tips & Best Practices

✅ **DO:**
- Use standard instruments for published research (better acceptance)
- Import instruments that match your study design
- Test the instrument with a few participants first
- Document which version you used in publications

❌ **DON'T:**
- Heavily modify validated instruments (affects validity)
- Skip step-by-step scoring if instrument requires it
- Use an instrument for something it wasn't designed for

### Troubleshooting

**"I don't see the Instrument Import section"**
- Make sure you're in the Home tab (not EDC or Reports)
- Refresh the page (Ctrl+R or Cmd+R)
- Check that you have admin access

**"The import seems to hang"**
- Wait 30 seconds (database write takes time)
- Check that your internet connection is stable
- Try importing a different instrument to test

**"I imported the wrong instrument"**
- Go to EDC tab → Delete the form
- Import the correct instrument

---

## Feature #2: Enhanced Field Types

### What Is It?

ZZedc now has 15+ different question types. Instead of just text boxes, you can use sliders, date pickers, checkboxes, file uploads, and more. This makes forms easier for participants and improves data quality.

### Available Field Types

#### Text-Based Fields

| Type | What It Looks Like | Best For |
|------|-------------------|----------|
| **Text** | Single-line text box | Names, IDs, short answers |
| **Email** | Email text box | Email addresses |
| **Textarea** | Large multi-line box | Detailed notes, comments |
| **Notes** | Extra-large text box | Long clinical notes |

#### Number & Date Fields

| Type | What It Looks Like | Best For |
|------|-------------------|----------|
| **Numeric** | Number box with +/- buttons | Ages, heights, weights, test scores |
| **Date** | Calendar picker | Birth dates, visit dates, event dates |
| **Time** | Time picker (hours:minutes) | Visit times, medication times |
| **DateTime** | Calendar + time picker | Precise timestamp for events |

#### Selection Fields

| Type | What It Looks Like | Best For |
|------|-------------------|----------|
| **Select** | Dropdown menu | Long lists (>5 options) |
| **Radio** | Circle buttons | 2-5 mutually exclusive options |
| **Checkbox** | Square checkboxes | Single yes/no option |
| **Checkbox Group** | Multiple checkboxes | Multiple selections (symptoms, etc.) |

#### Advanced Fields

| Type | What It Looks Like | Best For |
|------|-------------------|----------|
| **Slider** | Draggable slider | Pain level (1-10), satisfaction scales |
| **File** | File upload button | Documents, images, lab results |
| **Signature** | Signature pad | Consent forms, authorizations |

### Using Field Types in Your Forms

**When Creating a Form:**

1. **For a Pain Rating (0-10):**
   ```
   Field Name: pain_level
   Field Type: Slider
   Label: "On a scale of 0-10, how much pain are you experiencing?"
   Min: 0
   Max: 10
   ```
   → Participants drag a slider instead of typing

2. **For Symptom Selection (check all that apply):**
   ```
   Field Name: symptoms
   Field Type: Checkbox Group
   Label: "Which symptoms do you have?"
   Options: Pain, Fever, Cough, Fatigue, Nausea
   ```
   → Participants check multiple boxes easily

3. **For Consent Document Upload:**
   ```
   Field Name: signed_consent
   Field Type: File
   Label: "Upload your signed consent form"
   Accepted Files: PDF, JPG
   ```
   → Participants upload files directly

### Why Field Types Matter

**Better User Experience:**
- Participants understand exactly what's expected
- Fewer data entry errors
- Forms feel professional and modern

**Better Data Quality:**
- Date picker prevents invalid dates ("2024-99-99")
- Slider ensures numeric answers are in valid range
- Checkboxes prevent selecting mutually exclusive options

**Faster Data Entry:**
- Dropdown for common choices (faster than typing)
- Slider for scales (one swipe vs. typing)
- Calendar for dates (visual + accurate)

### Example: Creating a Visit Form with Multiple Field Types

```
Participant ID
  → Field Type: Text
  → Example: "STUDY-001"

Visit Date
  → Field Type: Date
  → Calendar picker for accuracy

Visit Time
  → Field Type: Time
  → Shows 09:00 AM format

Body Temperature
  → Field Type: Numeric
  → Format: 98.6 (Fahrenheit)

Current Medications (select all)
  → Field Type: Checkbox Group
  → Options: Aspirin, Ibuprofen, Acetaminophen, Other

Overall Health Rating
  → Field Type: Slider
  → Scale: 1 (Very Poor) to 10 (Excellent)

Clinical Notes
  → Field Type: Textarea
  → Large text box for doctor observations

Lab Results (PDF)
  → Field Type: File
  → Accept PDF only
```

**Result**: Professional, easy-to-use form that collects high-quality data.

### Tips & Best Practices

✅ **DO:**
- Use date picker for any birth dates or visit dates
- Use slider for pain/satisfaction scales (0-10)
- Use checkbox group for multiple symptoms
- Use file upload for supporting documents
- Test the form on mobile devices (smaller screens)

❌ **DON'T:**
- Use slider for >20 options (use select instead)
- Use file upload for data you could collect as text
- Mix similar field types on same form (confusing)
- Use required file uploads (participants may not have files)

### Troubleshooting

**"Time picker shows weird format"**
- This is normal if your computer uses 24-hour time
- Participants will see AM/PM or 24-hour format based on their region

**"Date picker shows wrong year"**
- Click the year to jump between years faster
- Use arrow buttons for month-by-month navigation

**"File upload is taking too long"**
- Large files (>10MB) take longer
- Suggest participants compress/reduce file size
- Check your internet connection

---

## Feature #3: Quality Dashboard

### What Is It?

The Quality Dashboard shows you at a glance how complete your data is, how many participants have enrolled, and whether there are any problems you should fix. It updates automatically every minute so you always see current information.

### Dashboard Location

- **Where**: Home tab (visible when you log in)
- **Auto-Updates**: Every 60 seconds (no refresh needed)
- **Available to**: PIs, Coordinators, Data Managers, Admins

### Dashboard Sections

#### 1. Key Metrics (Four Cards)

**Total Records**
- How many participants have been enrolled
- Includes all participants (complete or incomplete)

**Complete Records**
- How many participants have finished all forms
- Use this to track enrollment progress

**% Incomplete**
- What percentage of participants haven't finished
- Helps identify who needs follow-up

**Flagged Issues**
- Number of problems the system detected
- Examples: missing data, out-of-range values, duplicate subjects

#### 2. Completeness by Form (Bar Chart)

Shows which forms have the most missing data:

```
PHQ-9:           ████████░░░░ 85%
Demographics:    ██████████░░ 92%
Lab Results:     ██░░░░░░░░░░ 15%  ← Problem!
Consent:         ██████████░░ 100%
```

**What to do:**
- Forms with <80% should be reviewed
- Check why specific forms are incomplete
- Send reminders to participants for incomplete forms

#### 3. Enrollment Timeline (Line Chart)

Shows how many participants you've enrolled over time:

```
     ^
50   |        /
40   |       /
30   |      /
20   |  /\/
10   |/
     └────────────── Time
```

**What it means:**
- Upward line = Good enrollment progress
- Flat line = No new enrollments recently
- Sudden drop = Possible problem (server down, study paused, etc.)

#### 4. Missing Data Summary (Table)

Shows which fields have the most missing data:

| Field | Total | Missing | % Complete |
|-------|-------|---------|-----------|
| Phone Number | 50 | 8 | 84% |
| Social Security | 50 | 15 | 70% |
| Middle Name | 50 | 22 | 56% |

**What to do:**
- Investigate fields with >10% missing
- Some fields optional? Mark as "not required" in form
- Some fields hard to collect? Simplify the question
- Data entry error? Check participant records

### How to Use the Dashboard

**Daily Use:**
1. Log in to ZZedc (dashboard appears automatically)
2. Glance at the 4 metric cards (top row)
3. Note the current enrollment number
4. Check completeness by form
5. If any form <80%, investigate why

**Weekly Review:**
1. Check enrollment timeline (is it on pace?)
2. Look at missing data by field
3. Contact participants with incomplete forms
4. Fix any data quality issues

**Monthly Report:**
1. Export the dashboard metrics
2. Create a report for your team
3. Adjust enrollment targets if needed
4. Plan for remaining months

### Understanding Quality Flags

The system automatically flags problems:

| Flag | Meaning | What to Do |
|------|---------|-----------|
| Low Enrollment | <50% of target | Check if study paused or slow recruiting |
| High Incomplete | >30% forms incomplete | Send reminder emails to participants |
| High Missing Data | >20% of field blank | Review form design, may be too complicated |
| Duplicate Subject | Same person enrolled twice | Contact participant, consolidate records |
| Out of Range | Value outside expected | Check participant didn't misunderstand |

### Tips & Best Practices

✅ **DO:**
- Check dashboard daily during active enrollment
- Follow up on incomplete records within 24 hours
- Investigate sudden drops in enrollment
- Use data to improve form design (confusing questions)
- Keep target enrollment in mind

❌ **DON'T:**
- Ignore quality flags for >1 week
- Let incomplete records accumulate (harder to find later)
- Delete forms because they have low completion (investigate first)
- Force participants to fill out forms they don't understand

### Troubleshooting

**"Dashboard shows 0 records but I have enrolled participants"**
- Wait 60 seconds for auto-update
- Refresh page (Ctrl+R or Cmd+R)
- Check that forms are actually saved (not just in edit mode)

**"Chart shows weird data**
- This usually means the data type is wrong (text vs number)
- Contact admin to check form configuration

**"Missing data % doesn't add up"**
- Missing data is calculated at field level, not form level
- Example: Form 80% complete = average of all fields

---

## Feature #4: Form Branching Logic (Conditional Questions)

### What Is It?

Branching logic (also called conditional display) lets you show or hide questions based on participant answers. This simplifies forms by only asking relevant questions.

**Example:**
```
"Are you pregnant?" → If YES, show: "When is your due date?"
                    → If NO, skip to next question
```

### Why Use Branching Logic?

**Benefits:**
- ✅ Forms feel shorter (only relevant questions visible)
- ✅ Less confusing (participants don't see irrelevant questions)
- ✅ Better data quality (skip logic prevents "N/A" answers)
- ✅ Professional appearance
- ✅ Matches industry standard (REDCap uses this)

### How Branching Logic Works

You set a **condition** (if/when) and then the form **shows or hides** a field.

#### Simple Example: Gender → Pregnancy Question

```
Question 1: What is your gender?
  Options: Male, Female, Other

Question 2: When is your due date?
  Show if: Question 1 = Female
```

**Participant Experience:**
- Male selects "Male" → Pregnancy question is hidden
- Female selects "Female" → Pregnancy question appears
- Other selects "Other" → Pregnancy question is hidden

#### Complex Example: Employment-Based Questions

```
Question 1: What is your employment status?
  Options: Employed, Unemployed, Student, Retired

Question 2: What is your employer?
  Show if: Q1 = Employed

Question 3: What school do you attend?
  Show if: Q1 = Student

Question 4: What was your last job?
  Show if: Q1 = Unemployed
```

### Setting Up Branching Logic (For Admins)

When creating a form, you can add branching rules:

**Step 1: Add Base Question**
```
Field: employment_status
Type: Select
Options: Employed, Unemployed, Student, Retired
```

**Step 2: Add Conditional Question**
```
Field: employer_name
Type: Text
Label: "What company do you work for?"
Show If: employment_status = Employed
```

**Step 3: Add Another Conditional**
```
Field: school_name
Type: Text
Label: "What school?"
Show If: employment_status = Student
```

### Available Operators

You can use different comparison types:

| Operator | Meaning | Example |
|----------|---------|---------|
| **=** | Equals exactly | gender = Female |
| **≠** | Does not equal | status ≠ inactive |
| **<** | Less than | age < 65 |
| **>** | Greater than | age > 18 |
| **≤** | Less than or equal | score ≤ 50 |
| **≥** | Greater than or equal | score ≥ 18 |
| **in** | In a list | state in (CA, NY, TX) |

### Real-World Examples

#### Example 1: Clinical Trial

```
"Were you diagnosed with diabetes?"
  → If YES, show: "When diagnosed?" (date picker)
  → If NO, skip to next section
```

#### Example 2: Medication Study

```
"Do you take any medications?"
  → If YES, show:
     - Which medications?
     - How often?
     - Any side effects?
  → If NO, go to next section
```

#### Example 3: Safety Assessment

```
"Have you experienced any adverse events?"
  → If NO, skip to next form
  → If YES, show:
     - Event description (text)
     - Date of event (date picker)
     - Severity (slider 1-10)
     - Required hospitalization?
       → If YES, show: Hospital name, dates, etc.
       → If NO, continue
```

### Tips & Best Practices

✅ **DO:**
- Use branching to reduce form length
- Test all branches (participant paths) before deploying
- Use clear, specific conditions
- Document your branching logic for team

❌ **DON'T:**
- Create overly complicated branching (>3 levels deep)
- Hide required information (always ask critical questions)
- Use branching to create confusing question sequences
- Forget to test edge cases (all possible paths)

### Troubleshooting

**"A question appears but shouldn't be showing"**
- Wait for page to fully load (60 seconds)
- Refresh the page
- Check that condition was entered correctly

**"I can't find the branching logic option"**
- Contact your admin (requires configuration access)
- Branching logic is set up during form design

**"Participant says the form is confusing"**
- Review your branching logic
- Test with actual participants before rolling out
- Simplify conditions if possible

### Testing Your Branching Logic

Before going live with a form:

1. **Test with a test participant:**
   - Try answering YES to the conditional question
   - Verify hidden question appears
   - Try answering NO
   - Verify hidden question disappears

2. **Test all paths:**
   - If 3 options (Yes/No/Maybe), test each one
   - Make sure correct questions appear each time

3. **Test edge cases:**
   - What if participant changes their answer?
   - What if they skip a required field?

---

## Feature #5: Multi-Format Export

### What Is It?

Export lets you save your study data in different formats. Different software programs use different formats, so ZZedc lets you export to whichever format you need.

### Available Export Formats

| Format | File Type | Best For | Software |
|--------|-----------|----------|----------|
| **CSV** | .csv | Excel, databases | Universal (Excel, R, Python, etc.) |
| **XLSX** | .xlsx | Excel spreadsheets | Microsoft Excel |
| **JSON** | .json | Web apps, APIs | Programmers, APIs |
| **R Data** | .rds | R statistical analysis | R, RStudio |
| **SAS** | .xpt | SAS statistical software | SAS users |
| **SPSS** | .sav | SPSS statistical analysis | IBM SPSS, PSPP |
| **STATA** | .dta | Stata statistical software | Economists, social scientists |

### When to Use Each Format

**Choose CSV if:**
- You want a simple, universal format
- You'll open data in Excel
- You're not sure which format to use

**Choose XLSX if:**
- You're working in Microsoft Excel
- You need formatting (colors, formulas, multiple sheets)
- Your data is mostly numeric

**Choose JSON if:**
- You're a developer building an app
- You need data in web-friendly format

**Choose R (.rds) if:**
- You'll analyze data in R or RStudio
- You want the fastest file size and load time

**Choose SAS if:**
- Your team uses SAS for statistical analysis
- Your institution has SAS licenses

**Choose SPSS if:**
- Your team uses SPSS or PSPP
- Common in psychology and social science research

**Choose STATA if:**
- Your team uses Stata
- Common in economics and social science

### How to Export Your Data

**Step 1: Go to Export Tab**
- Click the **Export** tab at the top menu

**Step 2: Choose Your Settings**
- **Select data source**: EDC (clinical forms), Reports, or All Files
- **Choose format**: CSV, XLSX, JSON, R, SAS, SPSS, STATA
- **Optional settings**: Include metadata (who entered data, when), include timestamps

**Step 3: Click Export**
- Click **Generate Export**
- System creates the file with timestamp

**Step 4: Download**
- Click **Download [filename].csv** (or your chosen format)
- File downloads to your Downloads folder

**Step 5: Open in Your Program**
- Open the file in Excel, R, SPSS, or Stata
- Data is ready for analysis

### Example Exports

#### Example 1: Excel Analysis
```
1. Export as XLSX
2. Download to computer
3. Open in Microsoft Excel
4. Create pivot tables, charts, formulas
5. Share with team
```

#### Example 2: R Statistical Analysis
```
1. Export as R (.rds)
2. Download to computer
3. Open in RStudio:
   data <- readRDS("mydata.rds")
   summary(data)
4. Run statistical tests
```

#### Example 3: SPSS Data Analysis
```
1. Export as SPSS (.sav)
2. Download to computer
3. Open in IBM SPSS
4. Run statistical analyses
5. Generate publication-ready tables
```

### Understanding Your Exported Data

**What's in the export?**
- All participant records (complete and incomplete)
- All data entered into the system
- Column headers matching form field names
- Timestamps of data entry (optional)
- Metadata (who entered data, when)

**What's NOT in the export?**
- Passwords or login information
- Deleted records (only active records)
- Files uploaded to file fields (separate from data)

### Tips & Best Practices

✅ **DO:**
- Export regularly during active study (backup purposes)
- Choose CSV if unsure (universal format)
- Include timestamps (helps track data entry)
- Test export on your computer before analysis
- Keep export files with version numbers (e.g., data_v01, data_v02)

❌ **DON'T:**
- Share exported files without removing identifiers
- Overwrite old exports (keep versions)
- Export before data cleaning (wait until complete)
- Assume exported data is ready for analysis (always clean first)

### Handling Large Datasets

**For 10,000+ rows:**
- Use CSV or R (.rds) format (smaller file size)
- XLSX may be slow to open
- Avoid JSON (very large files)

**For very large files (>500MB):**
- Consider exporting date ranges instead
- Example: "Export data from Jan-Mar 2024"
- Then combine exports in Excel or R

### Troubleshooting

**"Export button is grayed out"**
- You may not have permission
- Contact your admin (exports need approval)

**"Export is taking a long time"**
- Large datasets take longer (normal)
- Wait at least 5 minutes before canceling
- Try a smaller export (fewer fields, fewer records)

**"Excel shows weird characters"**
- File may have different character encoding
- This usually happens with international characters
- Try opening in Google Sheets instead

**"R won't load my RDS file"**
- Make sure you're using the right command:
  ```r
  data <- readRDS("myfile.rds")
  ```
- Check that file is in your working directory

**"SPSS says file is corrupted"**
- Try re-exporting the data
- SPSS may need file with .sav extension (ensure it's there)

---

## Frequently Asked Questions

### General Questions

**Q: Can I use multiple features together?**
A: Yes! You can import an instrument (Feature #1), add branching logic (Feature #4), use enhanced field types (Feature #2), monitor with the dashboard (Feature #3), and export when done (Feature #5).

**Q: Do I need training to use these features?**
A: No! This guide covers everything. Most features are point-and-click.

**Q: Will these features slow down the system?**
A: No. All features are optimized for performance. The dashboard updates efficiently without impacting form entry.

**Q: Can I use these features with my existing study?**
A: Yes! These features work with existing data. No migration needed.

### Technical Questions

**Q: What if my browser doesn't support date picker?**
A: You'll see a text input box instead. Works the same, just different appearance.

**Q: Can I export to other formats not listed?**
A: CSV is the most universal. Any other format can be converted from CSV.

**Q: How often does the dashboard update?**
A: Every 60 seconds automatically. Refresh page for immediate update.

### Support & Escalation

**If you need help:**
1. Check this guide (likely has answer)
2. Check Release Notes (technical details)
3. Contact your local ZZedc admin
4. Contact the development team via GitHub

---

## Next Steps

### Getting Started

1. ✅ Read this guide (you're doing it!)
2. 📋 Test each feature with a test study first
3. 🚀 Deploy features for your real study
4. 📊 Monitor with Quality Dashboard
5. 📤 Export results when study complete

### For Your Team

1. Share this guide with all team members
2. Have a team training session
3. Assign someone to monitor the dashboard
4. Plan your export strategy before study ends
5. Test exports work in your analysis software

### Best Practices for Success

- **Plan your forms early** (use instruments library)
- **Test with participants** (catch usability issues)
- **Monitor data quality daily** (use dashboard)
- **Keep clean data** (use field types appropriately)
- **Export regularly** (backup + version control)
- **Document your process** (helps team consistency)

---

## Glossary

| Term | Meaning |
|------|---------|
| **Branching Logic** | Rules that show/hide questions based on answers |
| **Dashboard** | Display of real-time study metrics |
| **EDC** | Electronic Data Capture (form entry system) |
| **Export** | Saving data in a specific file format |
| **Field Type** | Type of input (text, number, date, etc.) |
| **Form** | Collection of related questions |
| **Instrument** | Pre-built, validated survey form |
| **Metadata** | Information about data (who entered it, when) |
| **Participant** | Person enrolled in the study |
| **Quality Flag** | Automatic alert about data problems |

---

## Contact & Support

**For Questions About:**

- **Using features** → This guide (or ask your local coordinator)
- **Technical problems** → Your ZZedc system admin
- **Database access** → Your IT department
- **Bug reports** → GitHub Issues (github.com/rgt47/zzedc)
- **Feature requests** → GitHub Discussions

**Emergency Support**
- System down? Contact your admin
- Can't export data? Try different format, then contact admin
- Lost participant data? Contact admin immediately (backups exist)

---

## Version Information

- **Guide Version**: 1.0
- **For ZZedc**: Version 1.1
- **Last Updated**: December 2025
- **Next Review**: June 2026

---

**You're ready to use ZZedc v1.1! Good luck with your research!** 🎉

Questions? See your system administrator or check the README file.
