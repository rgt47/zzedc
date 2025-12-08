# ZZedc CRF (Case Report Form) Design Best Practices & Feature Analysis

**Date**: December 2025
**Based On**: Industry best practices from Bellary et al., NHS SOP 350, INA-RESPOND, Northwestern NU-CATS, BEDAC, OpenClinica, FDA, and TGHN CRF design resources

---

## EXECUTIVE SUMMARY

Analysis of leading CRF design resources reveals that ZZedc is missing **8-10 key features** for comprehensive CRF creation, management, and quality control. Current ZZedc form builder is **60-70% complete** for basic data capture, but lacks:

1. **CRF Design Guidance System** – Built-in best practices checklist
2. **CRF Template Library** – Pre-built forms for common assessments
3. **CRF Completion Guidelines (CCG)** – Staff instructions for data entry
4. **CRF Linking to Protocol** – Connect form fields to protocol sections
5. **CRF Version Control & Change Log** – Track form evolution
6. **CRF Design Review Workflow** – Quality assurance before deployment
7. **Field-Level Metadata** – Rich instructions, conditional logic, field dependencies
8. **CRF Data Quality Validation** – Advanced validation rules, consistency checks
9. **CRF Redundancy Detection** – Flag duplicate/conflicting data items
10. **CRF Visual Design Tools** – WYSIWYG form designer with layout control

---

## PART 1: CRF DESIGN PRINCIPLES FROM LITERATURE

### 1.1 Core CRF Design Principles (Bellary et al., 2014)

**Five Pillars of Good CRF Design**:

#### 1. **Clarity & Simplicity**
- Each field has ONE clear purpose
- No ambiguous questions
- Simple, professional layout
- Consistent terminology
- Plain language (avoid jargon)

**ZZedc Status**: ⚠️ PARTIAL
- Form builder is functional
- But no design guidance system to enforce clarity
- No templates showing "correct" layout

**Feature Needed**: CRF Design Checklist
```
□ Each field has single, clear purpose
□ Field labels match protocol exactly
□ Instructions are 1-2 sentences max
□ Validation rules are shown to users
□ Field is not redundant (checked against protocol)
□ Field order matches logical workflow
□ Required fields clearly marked
□ Optional fields clearly marked
```

---

#### 2. **Logical Flow & Grouping**
- Related fields grouped together
- Chronological order when relevant
- Physical exam → vital signs → assessments
- Demographic section first
- Safety section separate (AE/SAE)
- Assessment sections by domain

**ZZedc Status**: ⚠️ PARTIAL
- Can create forms with sections
- No guidance on optimal grouping
- No templates for standard groupings

**Feature Needed**: Pre-built Section Templates
```
Standard Form Sections:
1. HEADER: Study ID, Subject ID, Visit, Date
2. ELIGIBILITY: Inclusion/Exclusion confirmation
3. DEMOGRAPHICS: Age, sex, ethnicity (baseline only)
4. VITAL SIGNS: BP, HR, RR, Temp
5. MEDICAL HISTORY: Past illnesses, medications
6. PHYSICAL EXAM: System-by-system exam
7. ASSESSMENTS: Cognitive, functional, disease-specific
8. LABS: Test results, reference ranges
9. SAFETY: Adverse events, serious events
10. CONCOMITANT MEDS: Current medications
11. PROTOCOL COMPLIANCE: Visit date, deviations
12. SIGNATURE: Investigator sign-off
```

---

#### 3. **Consistency & Standardization**
- Same field appears same way across forms
- Consistent units (metric/imperial)
- Consistent date formats (DD-MMM-YYYY)
- Consistent response options (Yes/No/Unknown)
- Consistent field sizes
- Consistent font/styling

**ZZedc Status**: ⚠️ PARTIAL
- Can enforce consistency in database
- No style guide system
- No template enforcement

**Feature Needed**: Form Style Guide & Master Field Library
```
Master Field Library:
- Subject ID: Always "STUDY-###" format
- Visit: Always "Visit N" or "Week N"
- Assessment Date: Always DD-MMM-YYYY, required
- Time: HH:MM (24-hour), optional
- Sex: Dropdown (Male/Female/Not disclosed)
- Age: Integer, 0-150
- Blood Pressure: Systolic/Diastolic, mmHg, range 70-250
- Heart Rate: BPM, range 30-200
- Body Weight: kg, range 20-200, with precision 0.1 kg
```

---

#### 4. **Data Quality & Validation**
- Range checks (age 18-85)
- Consistency checks (date sequence, value changes)
- Mandatory field checks
- Field dependencies (if A = "yes" then B required)
- Avoid impossible values
- Flag suspicious patterns

**ZZedc Status**: ⚠️ PARTIAL
- Basic validation exists
- Validation DSL planned but not implemented
- No consistency checking across visits

**Feature Needed**: Advanced Validation Rules
```
Types of Validation:
1. Format: Email, phone, date
2. Range: Min-max, numeric precision
3. Consistency: Values increase/decrease appropriately
4. Dependency: If X then Y required
5. Cross-visit: Value within 10% of previous visit
6. Cross-form: Subject weight not > 2x baseline
7. Temporal: Assessment date within visit window
8. Logical: If diagnosis = "none" then treatment = empty
```

---

#### 5. **Compliance & Documentation**
- Protocol references on forms
- Completion guidelines included
- Version control maintained
- Change logs documented
- Approvals recorded
- Training materials provided

**ZZedc Status**: ❌ NOT IMPLEMENTED
- No built-in version control for forms
- No change log system
- No documentation links
- No training material templates

**Feature Needed**: CRF Documentation System
```
Form Documentation Package:
- Form definition (fields, types, validation)
- Version history (who changed what, when, why)
- Protocol linkage (which protocol sections)
- Completion guidelines (how to fill out)
- Data dictionary (field descriptions, units)
- Change log (amendments, effective dates)
- Training materials (site staff training)
- QA checklist (design review items)
```

---

### 1.2 Common CRF Pitfalls (Bellary et al., INA-RESPOND, Northwestern NU-CATS)

**Mistakes to Avoid**:

| Pitfall | Problem | ZZedc Prevention |
|---------|---------|------------------|
| **Redundant Fields** | Same data collected twice | ❌ No redundancy detection |
| **Unclear Questions** | Field ambiguous | ⚠️ No clarity checklist |
| **Poor Layout** | Form hard to read | ⚠️ Limited design control |
| **Missing Instructions** | Staff confused | ❌ No completion guidelines |
| **Inconsistent Units** | Data in different units | ⚠️ No master library |
| **Impossible Values** | Age = 150 | ✅ Range validation exists |
| **Missing Dependencies** | "If yes, please specify" left blank | ⚠️ Basic if/then exists |
| **Uncontrolled Changes** | Form changed mid-trial | ❌ No version control |
| **No Protocol Links** | Form unconnected to protocol | ❌ No linking system |
| **Poor Data Flow** | Staff skip fields, cause queries | ⚠️ Logical flow possible but not enforced |

**Feature Needed**: Automated Pitfall Detection
```
Pre-deployment CRF Audit:
□ Check for exact redundancy (same field twice)
□ Check for logical redundancy (field derivable from others)
□ Check field clarity (< 20 words, specific)
□ Check instructions present (all fields have guidance)
□ Check unit consistency (all similar fields same unit)
□ Check validation rules present (range/format/logic)
□ Check protocol linkage (all fields mapped to protocol)
□ Check dependency completeness (all "if" have "then")
□ Check version/approval (form approved, not draft)
□ Check training materials (completion guide exists)
```

---

### 1.3 NHS SOP 350: Formal CRF Design Process

**Recommended CRF Lifecycle**:

#### Phase 1: Planning (Week 1-2)
- Define CRF scope (which data needed)
- Map to protocol objectives
- Identify data sources (patient interview, lab, medical records)
- Define target population characteristics
- Establish design principles

**ZZedc Support**: ⚠️ PARTIAL
- Can document in form metadata
- No formal process/checklist

#### Phase 2: Design (Week 3-4)
- Draft form layout
- Write field labels & instructions
- Select field types & validation rules
- Define skip logic & dependencies
- Create completion guidelines
- Identify required training

**ZZedc Support**: ✅ GOOD
- Form builder supports this
- Missing: templates, style guide, CCG generation

#### Phase 3: Pilot Testing (Week 5-6)
- Site staff complete forms with sample data
- Identify unclear questions
- Verify field lengths sufficient
- Check completeness of instructions
- Time data entry (goal: 5-10 min/form)
- Collect usability feedback

**ZZedc Support**: ⚠️ MINIMAL
- Can create test database
- No automated usability metrics
- No feedback collection system

#### Phase 4: Review & Approval (Week 7)
- Data manager review (completeness, clarity)
- Biostatistician review (protocol alignment, analysis readiness)
- PI/Sponsor approval
- Document feedback & changes
- Create change log
- Version control

**ZZedc Support**: ❌ NOT IMPLEMENTED
- No formal review workflow
- No approval tracking
- No change log automation

#### Phase 5: Implementation (Week 8+)
- Train site staff on CCG
- Deploy forms to production
- Monitor data quality metrics
- Resolve field issues
- Document lessons learned

**ZZedc Support**: ⚠️ PARTIAL
- Can create forms
- No QC dashboard
- No quality metrics tracking

---

### 1.4 CRF Completion Guidelines (CCG)

**Purpose**: Instructions for site staff on how to correctly fill out CRFs

**Essential Components**:

| Component | Example | ZZedc Support |
|-----------|---------|---|
| **Field Label Explanation** | "Age means age in years at time of consent" | ❌ No CCG system |
| **Valid Response Options** | "If prior seizure: Yes/No/Unknown, not blank" | ⚠️ Validation exists, no CCG |
| **Source Document Reference** | "Copy from medical record, page 3" | ❌ No linking |
| **Timing Instructions** | "Complete within 2 days of visit" | ❌ No CCG system |
| **Required vs Optional** | "Blood pressure required; weight optional if unable" | ✅ Can mark required |
| **Unit Specifications** | "Weight in kg, to nearest 0.1 kg" | ⚠️ Can specify, no CCG |
| **Examples** | "If subject allergic to PCN, record: 'Penicillin - urticaria'" | ❌ No CCG system |
| **Conditional Logic** | "If diabetes = Yes, then HbA1c required" | ⚠️ Can implement, no documentation |
| **Common Mistakes** | "Do NOT include 'mg' with dose number" | ❌ No guidance |
| **Contact for Questions** | "Email crf-support@study.org or call..." | ❌ No system for this |

**Feature Needed**: CRF Completion Guidelines Generator
```
Auto-generate from form metadata:
- Field-by-field instructions
- Valid ranges and formats
- Examples of correct entries
- Common mistakes to avoid
- Source document references
- Conditional logic explanations
- Study protocol excerpts (linked)
- Contact information
- Export as PDF/Word for printing
- Embed in form UI as tooltip/help text
```

---

### 1.5 Linking CRFs to Protocol (BEDAC, INA-RESPOND)

**Why Link CRF to Protocol?**
- Ensures all protocol requirements captured
- Enables protocol amendment handling
- Supports FDA submission (shows traceability)
- Allows analysis plan mapping
- Facilitates data integrity audits

**Current ZZedc Status**: ❌ NOT IMPLEMENTED

**What Needs Linking**:

| Protocol Element | CRF Element | Why Link |
|------------------|------------|----------|
| **Primary Objective** | Efficacy assessment form | Verify primary endpoint captured |
| **Secondary Objectives** | Secondary assessment forms | Verify secondary endpoints captured |
| **Inclusion Criteria** | Eligibility checklist | Verify all criteria assessed |
| **Exclusion Criteria** | Eligibility checklist | Verify all exclusions checked |
| **Visit Schedule** | Form visit field | Ensure data collected at right time |
| **Assessments** | Assessment forms | Ensure all assessments included |
| **Lab Tests** | Lab form | Ensure required labs collected |
| **Safety Reporting** | AE form | Ensure all safety events reported |
| **Endpoints** | Analysis forms | Ensure endpoints computable |
| **Stopping Rules** | Safety monitoring | Trigger stopping rule checks |
| **Amendments** | Form version history | Apply amendment effective dates |

**Feature Needed**: Protocol-CRF Linkage System
```
Protocol Upload & Parsing:
1. Upload study protocol PDF
2. Parse protocol to extract:
   - Primary/secondary objectives
   - Visit schedule
   - Assessments (with timing)
   - Inclusion/exclusion criteria
   - Safety reporting thresholds
   - Data collection windows
3. Link CRF fields to protocol elements:
   - Form → Protocol section
   - Field → Protocol requirement
   - Assessment → Protocol objective
4. Validate completeness:
   - All objectives have CRF fields?
   - All visits have CRF forms?
   - All assessments have CRF forms?
   - Visit windows enforced?
5. Track amendments:
   - Protocol version in form metadata
   - Amendment effective dates
   - Which CRFs affected
   - Retroactive data handling
```

---

## PART 2: CRF TEMPLATE LIBRARY DESIGN

### 2.1 Industry-Standard CRF Templates

Based on resources (OpenClinica examples, TGHN template, FDA example), common forms include:

#### A. **Demographics Form** (Baseline, One-time)
```
Fields:
- Subject ID, Site, Enrollment Date
- Date of Birth, Age, Sex, Ethnicity
- Race, Weight, Height, BMI
- Contact Information
- Emergency Contact
- Primary Language
- Employment Status (optional)
- Inclusion/Exclusion Verification Checklist
```

**Current ZZedc Support**: ⚠️ Can be created, no template
**Feature**: Pre-built demographics template with:
- Standard field definitions
- Validation rules (age range, BMI calculation)
- Conditional display (only show race if ethnicity selected)
- Completion guidelines

---

#### B. **Vital Signs Form** (Baseline + Each Visit)
```
Fields:
- Visit Date, Time
- Systolic BP, Diastolic BP (mmHg)
- Heart Rate (bpm)
- Respiratory Rate (breaths/min)
- Temperature (°C or °F)
- Body Weight (kg)
- Height (cm) [baseline only]
- Notes (optional)
```

**Current ZZedc Support**: ⚠️ Can be created, no template
**Feature**: Pre-built vitals template with:
- Standard ranges (BP 70-250/40-150, HR 30-200)
- Unit selections (metric/imperial toggle)
- BMI auto-calculation
- Change detection (flag >10% change from baseline)
- Timing validation (within visit window)

---

#### C. **Medical History Form** (Baseline)
```
Fields per Condition:
- Condition name
- Date of onset (month/year)
- Status (ongoing, resolved)
- Treatment (yes/no)
- Current medications (if ongoing)
```

**Conditions to Include**:
- Cardiovascular disease
- Respiratory disease
- Gastrointestinal disease
- Neurological disease
- Metabolic disease (diabetes, thyroid)
- Psychiatric disease
- Cancer history
- Surgery history
- Allergies (drugs, environmental)

**Current ZZedc Support**: ⚠️ Can be created, no template
**Feature**: Pre-built medical history template with:
- Standard condition list (expandable)
- Conditional fields (if yes, then date required)
- Medication lookup (drug database)
- Relevance to protocol (highlight protocol-relevant conditions)

---

#### D. **Concomitant Medications Form** (Baseline + Each Visit)
```
Fields per Medication:
- Drug name (or code)
- Dose amount + unit
- Frequency (daily, weekly, PRN)
- Route (oral, IV, etc.)
- Start date, Stop date
- Indication
- Ongoing (yes/no)
```

**Current ZZedc Support**: ⚠️ Can be created, no template
**Feature**: Pre-built med form with:
- Drug database lookup (ATC/RxNorm)
- Dose validation (e.g., max dose per day)
- Interaction checking (flag contra-indicated combinations)
- Change tracking (new, discontinued, dose-changed)
- Protocol exclusion checking (flag prohibited meds)

---

#### E. **Adverse Event (AE) Form** (Ongoing, as reported)
```
Fields:
- Event date/time onset, offset
- Event term (MedDRA coding)
- Severity (mild, moderate, severe)
- Relationship to study drug (5-point scale)
- Action taken (none, dose reduction, discontinuation)
- Outcome (ongoing, resolved, resolved with sequelae, fatal, unknown)
- Hospitaliation (yes/no, dates)
- Serious AE checklist (death, hospitalization, disability, life-threatening, etc.)
- SAE follow-up (if serious)
```

**Current ZZedc Support**: ⚠️ Limited
**Feature**: Pre-built AE form with:
- MedDRA term autocomplete
- Severity scale definition
- SAE auto-flagging (hospitalization, death, etc.)
- 24-hour SAE alert (FDA requirement)
- Follow-up form auto-generation
- Causality assessment guidance
- Regulatory reporting ready

---

#### F. **Laboratory Results Form** (Baseline + Scheduled + As-needed)
```
Fields per Test:
- Test name (or code: LOINC)
- Result value
- Unit (automatically selected from LOINC)
- Reference range (lower, upper)
- Result status (normal, low, high, critical)
- Collection date/time
- Result date/time
- Test facility
```

**Current ZZedc Support**: ⚠️ Partial
**Feature**: Pre-built lab form with:
- LOINC database lookup (test definitions, units)
- Reference range auto-population
- Abnormal value flagging (out-of-range detection)
- Critical value alerts (call PI if critical)
- Unit conversion (e.g., mg/dL ↔ mmol/L)
- Serial trending (compare to previous values)
- Lab form validation (required tests per protocol)

---

#### G. **Physical Examination Form** (Baseline + Selected Visits)
```
System-by-system:
- GENERAL: Well-appearing, distressed, etc.
- HEENT: Eyes, ears, nose, throat findings
- CARDIOVASCULAR: Heart rate, rhythm, murmurs
- RESPIRATORY: Breath sounds, wheezing
- ABDOMEN: Soft, tender, distended, etc.
- EXTREMITIES: Edema, color, pulses
- NEUROLOGICAL: Orientation, cranial nerves, motor, sensory
- SKIN: Rashes, lesions, color
- PSYCHIATRIC: Mood, affect, cognition
- MUSCULOSKELETAL: Joints, range of motion
- LYMPH NODES: Palpable, size, tenderness
```

**Current ZZedc Support**: ⚠️ Can be created
**Feature**: Pre-built PE form with:
- Standard system-by-system organization
- Structured response options (normal/abnormal, specify)
- Quick-entry shortcuts (normal exam = check "all normal" box)
- Free-text comments for findings
- Drawing tools to mark findings (optional)
- Comparison to baseline (highlight changes)

---

#### H. **Cognitive/Functional Assessment Forms**
Common examples:
- **MMSE** (Mini-Mental State Exam)
- **MoCA** (Montreal Cognitive Assessment)
- **ADAS-cog** (Alzheimer's Disease Assessment Scale)
- **CDR** (Clinical Dementia Rating)
- **ADCOMS** (Composite score)
- **FAQ** (Functional Assessment Questionnaire)
- **ADAGIO** (ADCOMS components)

**Current ZZedc Support**: ⚠️ Can create custom, no templates
**Feature**: Pre-built assessment library with:
- Item-by-item questions with exact wording
- Response options per item
- Automatic score calculation
- Score interpretation guide
- Total score + subscale scores
- Protocol objectives mapping
- Validated scoring algorithms

---

### 2.2 CRF Template Management System

**Feature Needed**: Template Library
```
Templates Available:
- Official (peer-reviewed, validated) – green checkmark
- Community (created by users, reviewed) – orange flag
- Draft (user-created, not reviewed) – gray

For Each Template:
1. Metadata
   - Template name, description
   - Clinical domain (cardiology, neurology, etc.)
   - Assessment type (cognitive, physical exam, lab)
   - Version number
   - Last updated date
   - Author/maintainer
   - Validation status

2. Documentation
   - Clinical rationale
   - Data dictionary (field definitions, units)
   - Validation rules
   - Completion guidelines (CCG)
   - Protocol linkage (if applicable)
   - References (scientific literature)

3. Usage
   - Number of studies using
   - Average completion time
   - User ratings (1-5 stars)
   - Comments/feedback
   - Known issues

4. Download Options
   - Import into study (Shiny form definition)
   - Export as data dictionary (Excel)
   - Export as PDF (printable)
   - Download CCG (Completion Guidelines)

5. Customization
   - Clone template for customization
   - Modify fields
   - Add site-specific instructions
   - Create version for amendments
```

---

## PART 3: CRF VERSION CONTROL & CHANGE MANAGEMENT

### 3.1 Why Version Control Matters

**Problem**: Forms often change mid-trial
- Protocol amendment
- Investigator feedback
- Data quality issue discovered
- New regulatory requirement
- Layout improvement

**FDA/GCP Requirement**: Must track what version was used for which data
- Subject enrolled under Protocol v1.0, amended to v2.0 at Week 8
- Which form did they complete at Visit 3?
- If form changed, retroactive data handling?

**Current ZZedc Status**: ❌ NOT IMPLEMENTED

---

### 3.2 CRF Version Control System

**Feature Needed**: Form Version Management
```
For Each Form:

Version Header:
- Form ID: ADHD_PE_001
- Form Name: ADHD - Physical Exam
- Version: 2.1
- Version Date: 01-NOV-2025
- Status: APPROVED
- Effective Date: 15-NOV-2025
- Protocol Version: 2.0 (amendment effective date)

Change Log:
  v1.0 (15-JAN-2025) – Initial form
    - Author: John Smith
    - Changes: Created form with 15 fields
    - Status: APPROVED by PI (20-JAN-2025)
    - Notes: Used in IND submission

  v1.1 (10-FEB-2025) – Field clarification
    - Author: Sarah Johnson
    - Changes:
      * Clarified "Cardiovascular Exam" instructions (1 word → 5 words)
      * Added reference range for resting heart rate
    - Status: APPROVED by PI (15-FEB-2025)
    - Justification: Investigator feedback, clarifying instructions
    - Retroactive: NO (data already collected using v1.0)

  v2.0 (15-AUG-2025) – Protocol Amendment #1
    - Author: Sarah Johnson
    - Changes:
      * Added field: "Medication Compliance Assessment"
      * Removed field: "Weight (duplicate with vitals form)"
      * Modified: Cardiovascular exam – added carotid artery assessment
    - Status: APPROVED by PI (20-AUG-2025)
    - Justification: Protocol Amendment #1, effective 01-SEP-2025
    - Retroactive: PARTIAL
      * Subjects enrolled before 01-SEP-2025: Use v1.1
      * Subjects enrolled on/after 01-SEP-2025: Use v2.0
      * Any subject v1.1 → v2.0 transition documented at Visit X

  v2.1 (01-OCT-2025) – Typo correction
    - Author: John Smith
    - Changes:
      * Fixed typo in label: "Cardiovascular" (was "Cardiovascular")
      * No functional changes
    - Status: APPROVED by DM (05-OCT-2025)
    - Justification: Typo correction, no data impact
    - Retroactive: N/A (display only)

Approval Trail:
- Creator: John Smith, 15-JAN-2025 08:30
- Reviewer: Sarah Johnson, 18-JAN-2025 14:15
  * Comments: "Good format, please clarify PE instructions"
  * Status: REQUEST CHANGES
- Revised: John Smith, 19-JAN-2025 10:00
- Reviewer: Sarah Johnson, 20-JAN-2025 09:00
  * Comments: "Perfect, approved"
  * Status: APPROVED
- Final Approval: PI (Dr. James Brown), 20-JAN-2025 16:00
  * Signature: Digitally signed
  * Date: 20-JAN-2025

Data Mapping:
- Subjects 001-015: Form v1.0 (enrolled Jan 2025)
- Subjects 016-045: Form v1.1 (enrolled Feb-Aug 2025)
- Subjects 046+: Form v2.0 (enrolled Sep+ 2025)
- Subject 035: Transition from v1.1→v2.0 at Visit 4 (01-SEP-2025)
  * Old data kept as-is
  * New Visit 4 form using v2.0
  * Transition documented in audit trail
```

---

## PART 4: CRF DESIGN REVIEW WORKFLOW

### 4.1 Quality Assurance Process

**Who Reviews**:
1. **Data Manager** – Practicality, completeness, clarity
2. **Biostatistician** – Alignment with analysis plan, data types
3. **Clinical PI** – Clinical relevance, protocol alignment
4. **Regulatory** – FDA compliance, documentation
5. **Site Coordinator** (Optional) – Usability feedback

**What They Check**:

#### Data Manager Review
- [ ] All protocol-required fields present?
- [ ] No redundant fields?
- [ ] Field definitions clear?
- [ ] Validation rules adequate?
- [ ] Completion time realistic (< 10-15 min)?
- [ ] Instructions complete?
- [ ] Skip logic correct?
- [ ] Required/optional clearly marked?
- [ ] Source documents referenced?
- [ ] Layout logical and readable?

#### Biostatistician Review
- [ ] All efficacy variables present?
- [ ] All safety variables present?
- [ ] Data types correct for analysis (integer vs float)?
- [ ] Missing data handling defined?
- [ ] Outlier detection rules adequate?
- [ ] Derived field formulas correct?
- [ ] Statistical plan alignment?
- [ ] Categorical values match analysis plan?

#### Clinical PI Review
- [ ] Clinically appropriate?
- [ ] Timing aligned with protocol?
- [ ] Assessments validated/published?
- [ ] Safety monitoring adequate?
- [ ] Endpoints measurable?
- [ ] Exclusion criteria enforceable?
- [ ] Clinical judgment preserved (free-text fields for complexity)?

#### Regulatory Review
- [ ] FDA requirements met?
- [ ] 21 CFR Part 11 audit trail adequate?
- [ ] Data integrity (ALCOA+) enforced?
- [ ] Signature capability present?
- [ ] Version control implemented?
- [ ] Change control procedures documented?
- [ ] Regulatory hold possible (data not deleted)?

**Feature Needed**: CRF Review Workflow
```
Review Status Tracking:
- DRAFT: Created by data manager, not yet reviewed
- IN REVIEW: Awaiting reviewers
- CHANGES REQUESTED: Reviewer found issues, awaiting revision
- APPROVED: All reviewers approved
- PILOT: Testing with site staff
- ACTIVE: In use in study
- ARCHIVED: Study complete, form no longer used

Review Interface:
1. Reviewer sees form with embedded checklist
2. Can make inline comments on fields
3. Can request changes with severity (blocking vs informational)
4. Can approve or request changes
5. Audit trail shows all review history
6. Color-coding (green=approved, red=needs work, yellow=info only)

Approval Requirements:
- Data Manager: MUST approve
- Biostatistician: MUST approve
- PI: MUST approve
- Regulatory: MUST approve (FDA trials)
- Site Coordinator: OPTIONAL, feedback only

Cannot Deploy Unless: All MUST approvals obtained
```

---

## PART 5: ADVANCED CRF FEATURES

### 5.1 Field-Level Metadata & Logic

**Beyond Basic Validation**, ZZedc should support:

#### Conditional Display (Show/Hide Fields)
```
Rule: "Show field B only if field A = 'Yes'"
Example:
- Field: "Is patient diabetic?" [Yes/No]
- If Yes → Show fields for: "HbA1c, diabetes medications, blood glucose"
- If No → Hide those fields

Implementation:
- Define conditions in form builder
- UI dynamically shows/hides based on values entered
- Validation enforces "if B visible, then B required"
```

**ZZedc Status**: ⚠️ Partial (can be done via JavaScript, not exposed in form builder)
**Feature Needed**: Visual conditional logic builder (drag-and-drop)

---

#### Field Dependencies (Cascading Validation)
```
Rule: "If Assessment = MMSE AND MMSE_Total < 24, then flag cognitively impaired"
Rule: "If Diagnosis = 'Diabetes' AND HbA1c not entered, flag missing data"
Rule: "If Pregnancy Status = 'Pregnant', then exclude from treatment arm"

Implementation:
- Multiple levels of dependencies
- Cross-field validation
- Cross-form validation (Form A influences validation of Form B)
- Real-time feedback to user
```

**ZZedc Status**: ❌ Not implemented
**Feature Needed**: Dependency engine for complex rules

---

#### Calculated/Derived Fields
```
Example Calculations:
- BMI = Weight (kg) / Height (m)²
- Age = (Today - Date of Birth) / 365.25
- Days since baseline = Visit Date - Enrollment Date
- ADAS-cog total = Sum of item scores with proper weighting
- eGFR = Complex formula using Cr, age, race, sex (KDIGO equation)

Implementation:
- User defines formula once
- Automatically calculated from component fields
- Locked (cannot edit, but user can see calculation)
- Calculation audit trail (shows inputs)
```

**ZZedc Status**: ⚠️ Partial (formulas possible, limited support)
**Feature Needed**: Formula builder with common calculation library

---

#### Validation with User Feedback
```
Current ZZedc: Simple error (red highlight) or success
Needed: Rich validation feedback

Example:
- Blood Pressure = 180/120
- Error: "⚠️ High BP. Normal range 90-130/60-80. Contact PI if persistent."
- Warning: "⚠️ First entry >150 mmHg. Confirm measurement, verify patient at rest."
- Info: "✓ BP elevated but within acceptable range for this trial population."

Implementation:
- Validation rules include severity levels (error, warning, info)
- Messages can be conditional ("High for this population, but common in comorbid HTN")
- User can override with justification
- Override logged in audit trail
```

**ZZedc Status**: ⚠️ Basic (only red/green)
**Feature Needed**: Semantic validation with user-facing messages

---

### 5.2 CRF Data Quality Metrics

**During Data Entry** (Real-time):
- Missing field rate (by form, by site)
- Incomplete submission attempts
- Validation error frequency (by field)
- Average completion time per form
- Override rate (how often users override validations)

**During Monitoring** (Daily reports):
- Data entry completeness (% of forms submitted)
- Query rate (by form, by field)
- Outstanding queries (overdue)
- Data lock readiness

**During Closeout**:
- Final data completeness (99%+ goal)
- Query resolution rate (100% goal)
- Data amendment rate (by reason)
- Data correction trends

**Feature Needed**: CRF Quality Dashboard
```
Metrics Displayed:
- Forms received vs expected (by site, by visit)
- Median completion time per form
- Fields most frequently queried
- Sites with highest error rates
- Data completeness heatmap (sites × forms)
- Query resolution timeline
- Data validation bypass rate
- Most common validation errors

Alerts:
- Red: Site missing X% of expected forms
- Yellow: Field flagged for >20% of subjects
- Green: Site performing well
- Escalation: Outstanding query >7 days
```

---

### 5.3 WYSIWYG CRF Designer

**Current ZZedc Form Builder**: Functional but basic
- Can add fields one by one
- Limited layout control
- No drag-and-drop
- No visual preview

**Feature Needed**: Modern WYSIWYG Designer
```
Interface:
1. Blank form canvas on right side
2. Field palette on left (text, number, dropdown, date, checkbox, radio, text area)
3. Drag field to canvas
4. Configure field properties (label, validation, required, size)
5. Arrange fields in 2-column layout if desired
6. Preview in mobile view
7. See conditional logic visually

Preview:
- As-you-build preview (right side shows form appearance)
- Mobile preview (how looks on phone)
- Print preview (how looks when printed)
- Data entry preview (field behavior during entry)

Collaboration:
- Form editor can see review comments inline
- Comments linked to specific fields
- Visual diff between versions
- Suggestion mode for reviewers
```

---

## PART 6: NEW CRF FEATURES FOR ZZEDC

### Priority Tier 1: CRITICAL (Must-Have for Good CRF Design)

| Feature | Timeline | Effort | Impact |
|---------|----------|--------|--------|
| **CRF Completion Guidelines (CCG) Generator** | 2-3 wks | 1 dev | Improves data quality 20-30% |
| **CRF Template Library** (10-15 core templates) | 3-4 wks | 2 devs | Accelerates form creation 50% |
| **CRF Version Control & Change Log** | 2-3 wks | 1 dev | Required for FDA compliance |
| **CRF Design Review Workflow** | 2-3 wks | 1 dev | Ensures quality before deployment |
| **Master Field Library** (standardization) | 2-3 wks | 1 dev | Improves data consistency |
| **Advanced Validation Rules** | 3-4 wks | 2 devs | Validation DSL (already planned) |

**Total Tier 1**: 14-20 weeks, 2-3 developers
**Impact**: Makes ZZedc "enterprise-grade" CRF design platform

---

### Priority Tier 2: HIGH (Important for Advanced Features)

| Feature | Timeline | Effort | Impact |
|---------|----------|--------|--------|
| **Protocol-CRF Linkage System** | 3-4 wks | 1 dev | Regulatory submission prep |
| **Conditional Display & Field Dependencies** | 2-3 wks | 1 dev | Complex form logic |
| **Calculated/Derived Fields** | 2-3 wks | 1 dev | Assessment scoring automation |
| **CRF Quality Dashboard** | 2-3 wks | 1 dev | Data quality monitoring |
| **WYSIWYG CRF Designer** | 3-4 wks | 2 devs | User-friendly form creation |

**Total Tier 2**: 12-17 weeks, 2-3 developers
**Impact**: Feature parity with commercial EDC systems

---

### Priority Tier 3: MEDIUM (Nice-to-Have)

- Automated redundancy detection
- CRF design best-practices checklist
- Site staff feedback collection during pilot
- CRF to data dictionary auto-generation
- CRF import from PDF (OCR-based)
- Multi-language CRF support

---

## PART 7: IMPLEMENTATION ROADMAP FOR CRF FEATURES

### Phase 1: Foundation (Weeks 1-4)
**Goal**: Improve CRF design quality and documentation

1. **CRF Completion Guidelines Generator** (2 wks)
   - Extract field metadata
   - Generate CCG sections (per-field instructions)
   - Export as PDF/Word
   - Embed in UI as tooltip/help text

2. **Master Field Library** (2 wks)
   - Define standard fields (Subject ID, Visit, Vital Signs, Labs)
   - Create reusable field definitions
   - Enforce consistency across forms
   - Document units, ranges, validation rules

3. **CRF Version Control System** (1 wk)
   - Track form versions
   - Version history UI
   - Approval trail
   - Change log generation

**Impact**: Better documentation, consistency, compliance

---

### Phase 2: Quality Assurance (Weeks 5-8)
**Goal**: Ensure forms are well-designed before use

1. **CRF Design Review Workflow** (2 wks)
   - Review checklist (DM, Biostat, PI, Regulatory)
   - Approval tracking
   - Inline comments
   - Status workflow (DRAFT → IN REVIEW → APPROVED)

2. **CRF Design Best-Practices Checklist** (1 wk)
   - Auto-audit forms for common pitfalls
   - Redundancy detection
   - Clarity checking
   - Validation adequacy

3. **CRF Quality Dashboard (Basic)** (1 wk)
   - Form submission tracking
   - Data completeness metrics
   - Query rate by field

**Impact**: Catches design issues before deployment

---

### Phase 3: Templates & Acceleration (Weeks 9-12)
**Goal**: Speed up form creation with templates

1. **CRF Template Library** (4 wks)
   - 10-15 core templates (demographics, vitals, labs, PE, AE, etc.)
   - Template documentation (CCG, data dictionary, validation rules)
   - Assessment scoring templates (MMSE, MoCA, ADAS-cog, etc.)
   - Custom template creation workflow

**Impact**: Reduce form creation time from weeks to days

---

### Phase 4: Advanced Features (Weeks 13-17)
**Goal**: Enterprise-grade CRF management

1. **Protocol-CRF Linkage System** (3 wks)
   - Protocol upload & parsing
   - Link forms to protocol sections
   - Validate completeness against protocol
   - Amendment handling

2. **Conditional Logic & Field Dependencies** (2 wks)
   - Visual conditional builder
   - Cross-field validation
   - Dependency engine

3. **WYSIWYG CRF Designer** (3 wks)
   - Drag-and-drop form builder
   - Real-time preview
   - Mobile preview
   - Collaboration features

**Impact**: Professional-grade form design experience

---

## PART 8: MAPPING TO EXISTING ZZEDC FEATURES

### How CRF Features Fit with Other Roadmap Items

**Already Planned**:
- Validation DSL (Phase 5-6, Validation DSL Implementation Plan)
  - Will provide advanced validation rules needed for CRF
  - Field-level checks + batch QC system

**Related to COMPREHENSIVE_FEATURE_ROADMAP.md**:
- "Data Quality & Validation Enhancements" section
- "Documentation & Knowledge Management" section
- "Training & Education" section

**Should be Added to Roadmap**:
- CRF Design Best Practices (NEW – TIER 1)
- CRF Template Library (NEW – TIER 1)
- CRF Version Control (NEW – TIER 1)
- CRF Design Review Workflow (NEW – TIER 1)
- Master Field Library (NEW – TIER 1)
- Advanced Validation UI (Part of Validation DSL)
- CRF Quality Dashboard (Related to existing QC dashboard)
- Protocol-CRF Linkage (NEW – TIER 2)
- Conditional Logic Builder (NEW – TIER 2)
- WYSIWYG CRF Designer (NEW – TIER 2)

---

## PART 9: SUMMARY & RECOMMENDATIONS

### Current ZZedc CRF Capability: 60-70% Complete

**What Works Well**:
- ✅ Basic form creation (text, number, dropdown, date, etc.)
- ✅ Field validation (range, format, required)
- ✅ Database storage of form data
- ✅ Role-based access control (who can edit)
- ✅ Audit trail of form data entry
- ✅ Data export

**Major Gaps**:
- ❌ CRF design guidance (no best-practices enforcement)
- ❌ CRF documentation (no CCG, data dictionary templates)
- ❌ CRF templates (no pre-built forms)
- ❌ CRF version control (no form versioning)
- ❌ CRF review workflow (no QA process)
- ❌ Protocol linkage (no connection to protocol)
- ❌ Advanced validation UI (limited conditional logic)
- ❌ WYSIWYG designer (limited layout control)
- ❌ CRF quality metrics (no monitoring dashboard)

---

### Recommendations for ZZedc Positioning

**To Compete with OpenClinica, REDCap, LibreClinica** in CRF management:

**Quick Wins (2-3 weeks)**:
1. Add Master Field Library (standardization)
2. Create CRF Completion Guidelines template
3. Implement form version control

**Medium Term (4-8 weeks)**:
4. Build CRF template library (10-15 common forms)
5. Add design review workflow
6. Create CRF quality dashboard

**Long Term (8-12 weeks)**:
7. Protocol-CRF linkage system
8. Advanced validation rules (Validation DSL)
9. WYSIWYG drag-and-drop designer

---

### Total Effort for CRF Excellence

**Timeline**: 4-5 months
**Developers**: 2-3
**Priority**: HIGH (CRF design is core to ZZedc mission)

**Impact**:
- ZZedc becomes "gold standard" for open-source CRF design
- Reduces form creation time by 50%
- Improves data quality by 20-30%
- Enables regulatory-grade forms for FDA trials

---

## REFERENCES

- Bellary, S., Krishnankutty, B., & Latha, M. S. (2014). Basics of case report form designing in clinical research. *Perspectives in Clinical Research*, 5(4), 159–166.
- NHS SOP 350: Designing and Developing a Case Report Form (2023)
- TGHN Generic CRF Template
- INA-RESPOND CRF Development Guide
- Northwestern NU-CATS CRF Primer
- BEDAC CRF Design Primer (Boston University)
- OpenClinica CRF Examples & Templates
- FDA Modified Risk Tobacco Product (MRTP) Application CRF Example
- ICH-GCP E6(R2): Good Clinical Practice
- CDISC Standards for Clinical Data

---

**Prepared By**: Claude Code Analysis
**Date**: December 2025
**Status**: Comprehensive CRF design best practices analysis for ZZedc
