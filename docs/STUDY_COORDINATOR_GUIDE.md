# ZZedc Study Coordinator Guide

## Daily Operations Manual for Clinical Research Teams

### Document Information

- **Version**: 1.0.0
- **Date**: December 2025
- **Audience**: Study Coordinators, Research Assistants, Site Staff, Data Entry Personnel
- **Prerequisites**: Basic computer skills, familiarity with clinical research concepts

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [Daily Operations](#2-daily-operations)
3. [User and Role Administration](#3-user-and-role-administration)
4. [Form and Instrument Management](#4-form-and-instrument-management)
5. [Quality Control Procedures](#5-quality-control-procedures)
6. [Study Lifecycle Management](#6-study-lifecycle-management)
7. [Validation Rule Management](#7-validation-rule-management)
8. [Common Tasks Quick Reference](#8-common-tasks-quick-reference)

---

## 1. Getting Started

### 1.1 Logging In

1. Open your web browser (Chrome, Firefox, or Edge recommended)
2. Navigate to the ZZedc URL provided by your administrator
3. Enter your username and password
4. Click "Sign In"

**First-time login**: You will be prompted to change your temporary password. Choose
a strong password with at least 8 characters including uppercase, lowercase,
numbers, and special characters.

### 1.2 Understanding the Interface

After logging in, you will see the main navigation bar with these sections:

| Tab | Purpose |
|-----|---------|
| **Home** | Dashboard with study overview and quick actions |
| **EDC** | Electronic Data Capture - enter and edit subject data |
| **Reports** | Generate enrollment, quality, and statistical reports |
| **Data Explorer** | Browse and search collected data |
| **Export** | Download data in various formats |
| **Admin** | User management and system settings (if authorized) |

### 1.3 Understanding Your Role

ZZedc uses role-based access control. Your role determines what actions you can
perform:

| Role | Can Do | Cannot Do |
|------|--------|-----------|
| **Data Entry** | Enter data, view own entries | Edit others' data, export, admin |
| **Coordinator** | Enter/edit data, run reports, export | Manage users, system settings |
| **Data Manager** | All coordinator tasks, resolve queries, manage data | System administration |
| **Monitor** | View data, run reports, raise queries | Enter or edit data |
| **PI (Principal Investigator)** | Full data access, approve changes | System administration |
| **Admin** | Full system access | N/A |

### 1.4 Navigating Between Sites (Multi-Site Studies)

If your study involves multiple sites:

1. Look for the "Site" dropdown in the top navigation bar
2. Select your site to filter data and forms
3. Your site assignment determines which subjects you can view and edit

---

## 2. Daily Operations

### 2.1 Data Entry Workflow

#### Step 1: Select or Enroll a Subject

**To enroll a new subject:**

1. Navigate to **EDC** > **Enroll Subject**
2. Enter the Subject ID (follow your study's ID format)
3. Complete required enrollment fields:
   - Site (auto-filled if single-site user)
   - Enrollment date
   - Demographics as required
4. Click **Enroll Subject**
5. The system will confirm enrollment and display the subject's schedule

**To select an existing subject:**

1. Navigate to **EDC** > **Subject List**
2. Use the search box to find your subject by ID or name
3. Click on the subject row to open their record

#### Step 2: Select the Visit and Form

1. From the subject view, you will see the visit schedule
2. Click on the appropriate visit (e.g., "Screening", "Week 4", "Final")
3. Select the form to complete (e.g., "Vital Signs", "Lab Results")
4. Forms with complete data show a green checkmark
5. Forms with missing data show a yellow warning
6. Forms with queries show a red exclamation mark

#### Step 3: Enter Data

1. Fill in each field according to the source document
2. Required fields are marked with a red asterisk (*)
3. Validation errors appear immediately below the field in red
4. Use the **Tab** key to move between fields
5. Date fields: Click the calendar icon or type in YYYY-MM-DD format
6. Dropdown fields: Start typing to filter options

**Validation Messages:**

| Color | Meaning | Action Required |
|-------|---------|-----------------|
| Red | Value out of range or invalid | Correct the value |
| Yellow | Value unusual but allowed | Verify against source, can proceed |
| Green | Value accepted | No action needed |

#### Step 4: Save and Verify

1. Click **Save** to store the entered data
2. Review the confirmation message
3. Check that all required fields are complete
4. The form status will update (Complete/Incomplete/Has Queries)

**Auto-save**: ZZedc automatically saves your work every 60 seconds. However,
always click Save before leaving a form.

### 2.2 Editing Existing Data

#### Minor Corrections (No Approval Required)

For data entry corrections within 24 hours of initial entry:

1. Navigate to the form with the error
2. Click the field to edit
3. Make the correction
4. Enter a reason in the "Reason for Change" popup
5. Click **Save**

The original value and your correction are both recorded in the audit trail.

#### Data Corrections (May Require Approval)

For changes after 24 hours or to verified data:

1. Navigate to the form
2. Click **Request Correction** (or the pencil icon)
3. Select the field(s) to correct
4. Enter the new value
5. Provide a detailed reason for the correction
6. Attach supporting documentation if available
7. Click **Submit for Review**

The Data Manager or PI will review and approve/reject the change.

### 2.3 Handling Missing Data

#### Expected Missing Data

When data is intentionally not collected (e.g., visit not performed):

1. Leave the field blank
2. Select the appropriate "Not Done" reason:
   - Not applicable
   - Not done per protocol
   - Participant refused
   - Equipment failure
3. Document the reason in the comments field

#### Unexpected Missing Data

When data should exist but is unavailable:

1. Leave the field blank temporarily
2. Open a query against yourself: "Source document pending"
3. Follow up to obtain the source document
4. Complete the data entry when available
5. Close the query with resolution notes

### 2.4 End-of-Day Checklist

Before logging out each day:

- [ ] Verify all data entered today is saved
- [ ] Review any validation warnings and resolve if possible
- [ ] Check your query inbox and respond to open queries
- [ ] Ensure subject statuses are accurate
- [ ] Log out of the system (click your name > Sign Out)

---

## 3. User and Role Administration

*This section is for Coordinators, Data Managers, and Administrators*

### 3.1 Adding New Users

1. Navigate to **Admin** > **User Management**
2. Click **Add New User**
3. Complete the required fields:

| Field | Description | Example |
|-------|-------------|---------|
| Username | Login identifier (no spaces) | jsmith |
| Email | Contact email address | j.smith@example.org |
| Full Name | Display name | Jane Smith |
| Role | Access level | Coordinator |
| Site(s) | Assigned site(s) | Site 001 |
| Status | Active or Inactive | Active |

4. Click **Create User**
5. The system generates a temporary password
6. Send credentials securely to the new user (not via unencrypted email)

### 3.2 Modifying User Accounts

**To change a user's role or site assignment:**

1. Navigate to **Admin** > **User Management**
2. Find the user in the list
3. Click **Edit** (pencil icon)
4. Modify the desired fields
5. Click **Save Changes**
6. The user will see updated permissions on their next login

**To deactivate a user:**

1. Navigate to **Admin** > **User Management**
2. Find the user in the list
3. Click **Deactivate** (or toggle Status to Inactive)
4. Confirm the action
5. The user can no longer log in but their audit history is preserved

### 3.3 Password Resets

**User-initiated reset:**

1. On the login page, click "Forgot Password"
2. Enter registered email address
3. Check email for reset link (valid for 1 hour)
4. Set new password

**Administrator-initiated reset:**

1. Navigate to **Admin** > **User Management**
2. Find the user
3. Click **Reset Password**
4. System generates a temporary password
5. Securely communicate the temporary password to the user

### 3.4 Role Permissions Reference

| Permission | Data Entry | Coordinator | Data Manager | Monitor | PI | Admin |
|------------|------------|-------------|--------------|---------|-----|-------|
| View own site data | Yes | Yes | Yes | Yes | Yes | Yes |
| View all sites data | No | No | Yes | Yes | Yes | Yes |
| Enter new data | Yes | Yes | Yes | No | Yes | Yes |
| Edit own entries | Yes | Yes | Yes | No | Yes | Yes |
| Edit others' entries | No | Yes | Yes | No | Yes | Yes |
| Resolve queries | No | Yes | Yes | No | Yes | Yes |
| Raise queries | No | Yes | Yes | Yes | Yes | Yes |
| Run reports | No | Yes | Yes | Yes | Yes | Yes |
| Export data | No | Yes | Yes | Yes | Yes | Yes |
| Manage users | No | No | No | No | No | Yes |
| System settings | No | No | No | No | No | Yes |
| Approve corrections | No | No | Yes | No | Yes | Yes |
| Lock/unlock visits | No | No | Yes | No | Yes | Yes |

---

## 4. Form and Instrument Management

### 4.1 Understanding the Data Dictionary

The Data Dictionary defines all forms and fields in your study. Each field has:

- **Field Name**: Technical identifier (e.g., `sbp`)
- **Label**: Display text (e.g., "Systolic Blood Pressure")
- **Type**: Data type (text, number, date, dropdown, etc.)
- **Validation**: Rules for acceptable values
- **Required**: Whether the field must be completed

### 4.2 Using the Instrument Library

ZZedc includes pre-built validated instruments:

1. Navigate to **Admin** > **Instruments**
2. Click **Import from Library**
3. Browse available instruments:
   - PHQ-9 (Depression)
   - GAD-7 (Anxiety)
   - SF-36 (Quality of Life)
   - PROMIS measures
   - And many more
4. Select the instrument to preview
5. Click **Import to Study**
6. Configure display options and visit assignment
7. Click **Activate**

### 4.3 Creating Custom Forms

#### Using Google Sheets (Recommended for Non-Technical Users)

1. Open the provided Google Sheets template
2. For each field, enter:
   - Field name (lowercase, no spaces, use underscores)
   - Label (human-readable)
   - Type (text, integer, decimal, date, dropdown, etc.)
   - Validation rule (see Section 7)
   - Options (for dropdowns, comma-separated)
   - Required (yes/no)
3. Save the Google Sheet
4. In ZZedc, navigate to **Admin** > **Forms** > **Import**
5. Select "Import from Google Sheets"
6. Enter the Sheet URL or ID
7. Click **Preview** to review
8. Click **Import** to create the form

#### Using the Form Builder

1. Navigate to **Admin** > **Forms** > **Create New**
2. Enter form name and description
3. Add fields by clicking **Add Field**
4. Configure each field:
   - Drag to reorder
   - Click gear icon for advanced settings
5. Set up branching logic if needed (see Section 4.4)
6. Click **Save Draft** to save work in progress
7. Click **Publish** when ready for use

### 4.4 Branching Logic

Branching logic shows or hides fields based on other responses.

**Example**: Show pregnancy-related questions only if sex is Female

| If Field | Operator | Value | Then Show |
|----------|----------|-------|-----------|
| sex | equals | Female | pregnant, lmp_date, gravida |

**To set up branching:**

1. Open the form in edit mode
2. Click on the field that should be conditionally shown
3. Click **Add Condition**
4. Select the controlling field
5. Choose the operator (equals, not equals, greater than, etc.)
6. Enter the trigger value
7. Click **Save**

### 4.5 Visit Schedule Configuration

1. Navigate to **Admin** > **Visit Schedule**
2. Define each visit:

| Visit | Name | Window (Days) | Target Day | Forms |
|-------|------|---------------|------------|-------|
| V1 | Screening | -7 to 0 | -3 | Demographics, Medical History, Screening |
| V2 | Baseline | 0 to 3 | 0 | Vital Signs, Labs, Randomization |
| V3 | Week 4 | 25 to 31 | 28 | Vital Signs, Efficacy, AEs |
| V4 | Week 8 | 53 to 59 | 56 | Vital Signs, Efficacy, AEs, Labs |
| VF | Final | 81 to 87 | 84 | All assessments, Study Completion |

3. Assign forms to each visit
4. Set visit window dates
5. Click **Save Schedule**

---

## 5. Quality Control Procedures

### 5.1 Understanding the Query System

Queries are questions or issues raised about data that require clarification or
correction. The query workflow ensures data accuracy and creates an audit trail.

**Query States:**

| Status | Meaning | Action Required |
|--------|---------|-----------------|
| Open | Query raised, awaiting response | Site must respond |
| Answered | Site has responded | Monitor/DM reviews |
| Closed | Issue resolved | None |
| Cancelled | Query withdrawn | None |

### 5.2 Responding to Queries

1. Navigate to **Home** > **My Queries** (or click the query notification)
2. Review the query details:
   - Subject ID
   - Visit and Form
   - Field in question
   - Query text
   - Date raised
3. Investigate the source document
4. Enter your response:
   - If data is correct: Explain why (e.g., "Verified against source")
   - If data needs correction: Make the correction and note it
5. Attach supporting documentation if needed
6. Click **Submit Response**

**Query Response Best Practices:**

- Be specific and reference source documents
- "Per source document dated 2025-01-15, value is correct"
- "Corrected per physician note, original entry was transcription error"
- Avoid vague responses like "fixed" or "ok"

### 5.3 Raising Queries (Monitors and Data Managers)

1. Navigate to the subject and form with the issue
2. Click on the field in question
3. Click **Raise Query** (flag icon)
4. Select query type:
   - Data Clarification
   - Missing Data
   - Protocol Deviation
   - Consistency Check
   - Source Document Request
5. Enter the query text (be specific)
6. Set priority (High, Medium, Low)
7. Click **Submit Query**

**Example Query Texts:**

- "Please verify: BP reading of 180/95 is higher than typical for this subject.
  Was this value confirmed on re-measurement?"
- "Missing laboratory results for Visit 3. Please provide or mark as Not Done
  with reason."
- "Date inconsistency: Visit 3 date (2025-03-15) is before Visit 2 date
  (2025-03-20). Please clarify."

### 5.4 Reviewing Data Quality Reports

1. Navigate to **Reports** > **Quality Reports**
2. Select report type:
   - **Missing Data Report**: Lists all incomplete required fields
   - **Query Status Report**: Summary of open/closed queries by site
   - **Validation Failures**: Fields that triggered validation warnings
   - **Data Entry Timeliness**: Time between visit and data entry
3. Set filters (site, date range, visit)
4. Click **Generate Report**
5. Review findings and take action

### 5.5 Query Resolution Workflow

```
┌──────────────┐     ┌─────────────────┐     ┌──────────────────┐
│   Monitor    │     │   Coordinator   │     │   Data Manager   │
│  raises      │────▶│   responds to   │────▶│   reviews and    │
│  query       │     │   query         │     │   closes query   │
└──────────────┘     └─────────────────┘     └──────────────────┘
                              │
                              │ If data correction needed
                              ▼
                     ┌─────────────────┐
                     │   Coordinator   │
                     │   makes         │
                     │   correction    │
                     └─────────────────┘
```

### 5.6 Data Verification Checklist

Weekly review for each active subject:

- [ ] All scheduled visits have data entered
- [ ] No outstanding queries older than 7 days
- [ ] All required fields are complete
- [ ] No validation warnings unaddressed
- [ ] Visit dates are within protocol windows
- [ ] No duplicate data entries
- [ ] Adverse events properly documented

---

## 6. Study Lifecycle Management

### 6.1 Study Setup Phase

#### Before First Subject

1. **Configure Study Settings**
   - Navigate to **Admin** > **Study Settings**
   - Enter study name, protocol number, sponsor
   - Set enrollment targets by site
   - Configure visit schedule

2. **Set Up Forms**
   - Import or create all required forms
   - Test each form with sample data
   - Verify validation rules work correctly

3. **Create User Accounts**
   - Add all site staff with appropriate roles
   - Provide training before access granted
   - Document training completion

4. **Test Data Entry**
   - Create test subjects (use IDs like TEST001)
   - Complete full data entry for all visits
   - Verify reports generate correctly
   - Delete test data before go-live

### 6.2 Active Enrollment Phase

#### Daily Tasks

| Task | Frequency | Responsible |
|------|-----------|-------------|
| Enter new data | Daily | Data Entry / Coordinator |
| Respond to queries | Daily | Coordinator |
| Review dashboards | Daily | Data Manager |
| Backup verification | Daily | System Admin |

#### Weekly Tasks

| Task | Frequency | Responsible |
|------|-----------|-------------|
| Missing data review | Weekly | Coordinator |
| Query aging report | Weekly | Data Manager |
| Enrollment tracking | Weekly | PI / Coordinator |
| User access review | Weekly | Admin |

#### Monthly Tasks

| Task | Frequency | Responsible |
|------|-----------|-------------|
| Data quality metrics | Monthly | Data Manager |
| Site performance review | Monthly | Monitor |
| Protocol deviation log | Monthly | Coordinator |
| Audit log review | Monthly | Admin |

### 6.3 Maintenance Phase (After Enrollment Complete)

1. **Continue data collection** for follow-up visits
2. **Intensify query resolution** to achieve database lock readiness
3. **Begin data cleaning** systematic review
4. **Prepare for database lock**

### 6.4 Study Closeout Phase

#### Pre-Lock Checklist

Before requesting database lock:

- [ ] All subjects have completed final visits (or are documented as
      early terminations)
- [ ] All required forms are complete or documented as missing with reason
- [ ] Zero open queries (or documented exceptions approved by sponsor)
- [ ] All data corrections are complete
- [ ] All protocol deviations are documented
- [ ] Site PI has reviewed and signed off on site data
- [ ] Data Manager has completed final data review

#### Requesting Database Lock

1. Navigate to **Admin** > **Database Lock**
2. Run the **Lock Readiness Check**
3. Review any blocking issues
4. Resolve all blocking issues
5. Request lock approval from sponsor/DM
6. Once approved, execute lock
7. System prevents all further data changes

#### Post-Lock Activities

- Generate final data exports
- Archive audit trails
- Complete study-specific reports
- Maintain read-only access as required

### 6.5 Subject Status Management

#### Enrolling a Subject

See Section 2.1

#### Withdrawing a Subject

1. Navigate to the subject record
2. Click **Change Status**
3. Select "Withdrawn"
4. Select withdrawal reason:
   - Participant request
   - Lost to follow-up
   - Adverse event
   - Protocol violation
   - Other (specify)
5. Enter withdrawal date
6. Complete any required early termination forms
7. Click **Confirm Status Change**

#### Completing a Subject

1. Subject completes all protocol-required visits
2. Complete the Study Completion form
3. Change status to "Completed"
4. Document completion date
5. The subject is now closed to further data entry

---

## 7. Validation Rule Management

### 7.1 Introduction to Validation Rules

Validation rules ensure data quality by checking values as they are entered.
ZZedc uses a plain English language for defining rules that non-programmers
can create and maintain.

### 7.2 Using Google Sheets for Validation Rules

Your data dictionary Google Sheet includes a "Validation" column where you
enter rules using simple English syntax.

#### Basic Rule Syntax

| Rule Type | Syntax | Example |
|-----------|--------|---------|
| Range | `between X and Y` | `between 18 and 100` |
| Minimum | `>= X` or `at least X` | `>= 0` |
| Maximum | `<= X` or `at most X` | `<= 300` |
| Required | `required` | `required` |
| Pattern | `matches PATTERN` | `matches ###-##-####` |
| Options | `in(opt1, opt2, ...)` | `in('Yes', 'No', 'Unknown')` |

#### Conditional Rules

Show validation only under certain conditions:

```
if field == value then RULE endif
```

**Examples:**

```
# If female, pregnancy status is required
if sex == 'Female' then required endif

# If pregnant, gestational age must be provided
if pregnant == 'Yes' then between 0 and 42 endif

# Diastolic must be less than systolic
dbp < sbp
```

#### Cross-Field Validation

Reference other fields in the same form:

```
# End date must be after start date
end_date > start_date

# Weight change should be within 10% of baseline
weight within 10% of baseline_weight

# Visit date within window of scheduled date
visit_date within 7 days of scheduled_date
```

### 7.3 Common Validation Rule Examples

**Demographics Form:**

| Field | Validation Rule |
|-------|-----------------|
| age | `between 18 and 100` |
| sex | `in('Male', 'Female', 'Other')` |
| race | `in('White', 'Black', 'Asian', 'Other', 'Unknown')` |
| dob | `before today` |
| phone | `matches (###) ###-####` |

**Vital Signs Form:**

| Field | Validation Rule |
|-------|-----------------|
| sbp | `between 70 and 250` |
| dbp | `between 40 and 150` |
| dbp_vs_sbp | `dbp < sbp` |
| heart_rate | `between 40 and 200` |
| temperature | `between 95.0 and 105.0` |
| weight_kg | `between 30 and 300` |

**Laboratory Form:**

| Field | Validation Rule |
|-------|-----------------|
| hemoglobin | `between 5 and 20` |
| wbc | `between 1 and 50` |
| platelets | `between 50 and 1000` |
| creatinine | `between 0.1 and 15` |
| alt | `between 0 and 500` |

### 7.4 Importing Validation Rules

1. Complete your Google Sheet with validation rules
2. Navigate to **Admin** > **Validation Rules** > **Import**
3. Select your Google Sheet
4. Click **Preview** to review rules
5. Check for any syntax errors (shown in red)
6. Fix any errors in the Google Sheet
7. Click **Import**
8. Rules are now active for data entry

### 7.5 Rule Approval Workflow

Certain sensitive rules require PI approval before activation:

**Rules requiring approval:**

- Rules that reject previously valid data
- Rules with ranges outside standard clinical values
- Cross-form validation rules
- Rules marked as "hard stops" (block saving)

**Approval process:**

1. Submit rule for review
2. PI receives notification
3. PI reviews rule and supporting rationale
4. PI approves or requests modification
5. Upon approval, rule becomes active

### 7.6 Testing Validation Rules

Before deploying new rules to production:

1. Navigate to **Admin** > **Validation Rules** > **Test**
2. Select the rule to test
3. Enter sample values:
   - Valid values (should pass)
   - Invalid values (should fail)
   - Edge cases (boundary values)
4. Click **Run Test**
5. Verify expected behavior
6. Document test results

---

## 8. Common Tasks Quick Reference

### 8.1 Data Entry Quick Reference

| Task | Navigation | Steps |
|------|------------|-------|
| Enroll new subject | EDC > Enroll | Enter ID, demographics, save |
| Enter form data | EDC > Subject > Visit > Form | Fill fields, save |
| Edit existing data | EDC > Subject > Visit > Form | Click field, edit, reason, save |
| Request correction | Form > Request Correction | Select field, new value, reason, submit |

### 8.2 Query Management Quick Reference

| Task | Navigation | Steps |
|------|------------|-------|
| View my queries | Home > My Queries | Review list, sort by priority |
| Respond to query | My Queries > Select query | Enter response, submit |
| Raise query | Form > Field > Flag icon | Select type, enter text, submit |
| Close query | Query > Review response | Verify, close |

### 8.3 Reporting Quick Reference

| Report | Navigation | Use Case |
|--------|------------|----------|
| Enrollment | Reports > Basic > Enrollment | Track recruitment progress |
| Missing Data | Reports > Quality > Missing | Find incomplete forms |
| Query Status | Reports > Quality > Queries | Monitor query resolution |
| Data Export | Export > Select format | Get data for analysis |

### 8.4 Administrative Quick Reference

| Task | Navigation | Steps |
|------|------------|-------|
| Add user | Admin > Users > Add | Enter details, assign role |
| Reset password | Admin > Users > Select > Reset | Generate temp password |
| Import form | Admin > Forms > Import | Select source, preview, import |
| View audit log | Admin > Audit Trail | Set filters, search |

### 8.5 Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Tab` | Move to next field |
| `Shift+Tab` | Move to previous field |
| `Ctrl+S` / `Cmd+S` | Save form |
| `Ctrl+Enter` | Submit and move to next form |
| `Esc` | Cancel current edit |
| `/` | Open search |
| `?` | Show help |

---

## Appendix A: Troubleshooting for Users

### Cannot Log In

1. Verify username spelling (case-sensitive)
2. Check Caps Lock is off
3. Try "Forgot Password" to reset
4. Contact your administrator if locked out

### Data Not Saving

1. Check for validation errors (red messages)
2. Verify required fields are complete
3. Check internet connection
4. Try refreshing the page (Ctrl+F5)
5. Contact support if issue persists

### Form Not Displaying

1. Clear browser cache
2. Try a different browser
3. Check if form is assigned to current visit
4. Verify you have permission for this form

### Report Taking Too Long

1. Narrow date range
2. Filter by site or subject
3. Try off-peak hours
4. Contact support for large exports

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| **AE** | Adverse Event - any untoward medical occurrence |
| **Audit Trail** | Chronological record of all system activities |
| **CRF** | Case Report Form - data collection instrument |
| **Data Dictionary** | Specification of all fields and their attributes |
| **EDC** | Electronic Data Capture |
| **Query** | Request for clarification about entered data |
| **SAE** | Serious Adverse Event |
| **Source Document** | Original record where data was first recorded |
| **Validation Rule** | Automated check for data accuracy |
| **Visit Window** | Acceptable date range for a protocol visit |

---

## Appendix C: Support Contacts

| Issue Type | Contact | Response Time |
|------------|---------|---------------|
| Password reset | Site administrator | Same day |
| Data entry questions | Study coordinator | Same day |
| System errors | IT support | 4 hours |
| Protocol questions | Study PI | 24 hours |
| Database issues | Data management center | 24 hours |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | December 2025 | ZZedc Team | Initial release |
