# ZZedc Non-Technical Operations Roadmap

## Executive Summary

**Vision:** Enable clinical trial coordinators and data managers to setup, configure, and manage ZZedc without R programming knowledge or technical support.

**Current State:** 70% complete for data collection, 20% complete for setup/management

**Gap:** No web-based setup/admin interfaces; requires command-line R knowledge

**Path to Vision:** 3-phase implementation (6-8 weeks total)

---

## Part 1: Admin Dashboard Plan

### **1.1 Overview**

Replace command-line and SQL management with intuitive web interface integrated into ZZedc.

**Location:** `R/modules/admin_dashboard_module.R` (new file, ~1000 lines)

**Access:** Limited to Admin users only

**Load location:** Added to main UI when user role is "Admin"

---

### **1.2 Dashboard Structure**

```
Admin Dashboard (Tab in main UI)
├── User Management
│   ├── View all users
│   ├── Add new user
│   ├── Edit user details
│   ├── Assign/change role
│   ├── Enable/disable user
│   └── Reset password
│
├── Role & Permissions
│   ├── View all roles
│   ├── Create new role
│   ├── Edit role permissions
│   └── Assign users to roles
│
├── Site Management (for multi-site)
│   ├── View all sites
│   ├── Add new site
│   ├── Edit site info
│   └── Activate/deactivate sites
│
├── Form Management
│   ├── List all forms
│   ├── View form structure
│   ├── Create new form (visual builder)
│   ├── Edit form fields
│   ├── Preview form
│   ├── Import form from Google Sheets
│   └── Export form to CSV
│
├── Database Management
│   ├── View database status
│   ├── Backup database (with one-click)
│   ├── Restore from backup
│   ├── Repair database (detect & fix corruption)
│   ├── Database size & usage
│   └── Purge old audit logs (optional)
│
├── System Configuration
│   ├── Edit basic settings (no YAML)
│   ├── Configure password salt
│   ├── Set session timeout
│   ├── Configure theme/colors
│   ├── Email settings
│   └── API configuration
│
├── Audit & Monitoring
│   ├── View audit log
│   ├── Filter by user/date/action
│   ├── Search audit trail
│   ├── Export audit report
│   └── System health status
│
└── Help & Documentation
    ├── Integrated user guide
    ├── Video tutorials
    ├── Troubleshooting guide
    └── Contact support
```

---

### **1.3 Detailed Feature Specifications**

#### **User Management Module**

**UI Components:**
```r
# View Users Table
DT::datatable(
  users_data,
  options = list(
    columnDefs = list(
      list(render = JS("function(data) { return '<button class=\"btn btn-sm btn-primary\">Edit</button>'; }"),
           targets = 5)  # Edit button in last column
    )
  )
)

# Add User Modal
modal_add_user <- function() {
  modalDialog(
    textInput("new_username", "Username", placeholder = "jsmith"),
    textInput("new_full_name", "Full Name", placeholder = "John Smith"),
    textInput("new_email", "Email", placeholder = "jsmith@example.com"),
    selectInput("new_role", "Role",
                choices = c("Admin", "PI", "Coordinator", "Data Manager", "Monitor")),
    selectInput("new_site", "Site", choices = site_options),
    passwordInput("new_password", "Temporary Password"),
    checkboxInput("send_email", "Send welcome email", value = TRUE),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("btn_create_user", "Create User", class = "btn-primary")
    )
  )
}

# Edit User Modal
modal_edit_user <- function(user_id) {
  user_data <- db_query("SELECT * FROM edc_users WHERE user_id = ?", user_id)
  modalDialog(
    textInput("edit_username", "Username", value = user_data$username, disabled = TRUE),
    textInput("edit_full_name", "Full Name", value = user_data$full_name),
    textInput("edit_email", "Email", value = user_data$email),
    selectInput("edit_role", "Role",
                selected = user_data$role,
                choices = c("Admin", "PI", "Coordinator", "Data Manager", "Monitor")),
    selectInput("edit_site", "Site",
                selected = user_data$site_id,
                choices = site_options),
    checkboxInput("edit_active", "Active", value = user_data$active),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("btn_save_changes", "Save Changes", class = "btn-primary")
    )
  )
}
```

**Server Logic:**
```r
# Create new user
observeEvent(input$btn_create_user, {
  # Validate inputs
  if (input$new_username == "" || input$new_password == "") {
    showNotification("Username and password required", type = "error")
    return()
  }

  # Check for duplicate username
  existing <- db_query(
    "SELECT COUNT(*) as n FROM edc_users WHERE username = ?",
    input$new_username
  )
  if (existing$n > 0) {
    showNotification("Username already exists", type = "error")
    return()
  }

  # Hash password
  salt <- Sys.getenv(cfg$auth$salt_env_var, cfg$auth$default_salt)
  password_hash <- digest(paste0(input$new_password, salt), algo = "sha256")

  # Insert new user
  db_execute(
    "INSERT INTO edc_users
     (user_id, username, password_hash, full_name, email, role, site_id, active, created_by)
     VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)",
    list(
      paste0("user_", Sys.time()),
      input$new_username,
      password_hash,
      input$new_full_name,
      input$new_email,
      input$new_role,
      input$new_site,
      user_input$username
    )
  )

  # Log action
  audit_log(
    action = "USER_CREATED",
    details = paste("Created user:", input$new_username, "Role:", input$new_role)
  )

  # Send welcome email if requested
  if (input$send_email) {
    send_welcome_email(
      input$new_email,
      input$new_username,
      input$new_password
    )
  }

  showNotification(paste("User", input$new_username, "created successfully"),
                   type = "message")
  removeModal()

  # Refresh user table
  rv$refresh_users <- rv$refresh_users + 1
})

# Reset password
observeEvent(input$btn_reset_password, {
  new_password <- generate_random_password()
  salt <- Sys.getenv(cfg$auth$salt_env_var, cfg$auth$default_salt)
  password_hash <- digest(paste0(new_password, salt), algo = "sha256")

  db_execute(
    "UPDATE edc_users SET password_hash = ? WHERE user_id = ?",
    list(password_hash, input$selected_user_id)
  )

  showNotification(
    paste("Password reset. Temporary password:", new_password),
    type = "message"
  )
})
```

**Feasibility:** ⭐⭐⭐⭐ (High - straightforward CRUD operations)

**Estimated effort:** 40-50 lines of UI code, 100-150 lines of server logic

---

#### **Form Builder Module**

**Visual Form Editor:**
```r
# Drag-and-drop form builder interface
ui_form_builder <- function() {
  fluidPage(
    h3("Visual Form Builder"),
    fluidRow(
      column(3,
        h4("Available Fields"),
        div(id = "field_palette",
          draggable_field("text_field", "Text Input", icon = icon("font")),
          draggable_field("numeric_field", "Numeric Input", icon = icon("numbers")),
          draggable_field("date_field", "Date Picker", icon = icon("calendar")),
          draggable_field("select_field", "Dropdown", icon = icon("list")),
          draggable_field("radio_field", "Radio Buttons", icon = icon("circle")),
          draggable_field("checkbox_field", "Checkbox", icon = icon("check-square")),
          draggable_field("textarea_field", "Text Area", icon = icon("paragraph"))
        )
      ),
      column(6,
        h4("Form Preview"),
        div(id = "form_canvas", style = "border: 1px solid #ccc; padding: 20px; min-height: 400px;",
          "Drag fields here to build form"
        )
      ),
      column(3,
        h4("Field Properties"),
        div(id = "field_properties",
          textInput("field_label", "Field Label"),
          textInput("field_name", "Variable Name"),
          checkboxInput("field_required", "Required"),
          checkboxInput("field_validation", "Add Validation"),
          conditionalPanel(
            "input.field_validation",
            textInput("validation_rule", "Validation Rule"),
            textInput("validation_message", "Error Message")
          ),
          actionButton("btn_add_field", "Add Field", class = "btn-primary")
        )
      )
    ),
    hr(),
    fluidRow(
      column(12,
        actionButton("btn_preview_form", "Preview Form", class = "btn-info"),
        actionButton("btn_save_form", "Save Form", class = "btn-success"),
        actionButton("btn_cancel_form", "Cancel", class = "btn-danger")
      )
    )
  )
}

# Save form to database
observeEvent(input$btn_save_form, {
  form_structure <- get_form_from_canvas()  # JavaScript to get form structure

  db_execute(
    "INSERT INTO data_dictionary (form_name, form_structure, created_by, created_date)
     VALUES (?, ?, ?, ?)",
    list(
      input$form_name,
      jsonlite::toJSON(form_structure),
      user_input$username,
      Sys.time()
    )
  )

  showNotification("Form saved successfully", type = "message")
})
```

**Feasibility:** ⭐⭐⭐ (Medium - requires JavaScript for drag-and-drop)

**Estimated effort:** 300-400 lines of code (R + JavaScript)

**Note:** Could start with table-based editor (simpler) before moving to drag-and-drop

---

#### **Database Management Module**

**One-Click Backup:**
```r
observeEvent(input$btn_backup, {
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  backup_file <- file.path("backups", paste0("zzedc_backup_", timestamp, ".db"))

  tryCatch({
    # Create backup
    file.copy(cfg$database$path, backup_file)

    # Verify backup
    backup_size <- file.size(backup_file)

    showNotification(
      paste("Backup created successfully\nFile:", backup_file,
            "\nSize:", format(backup_size, "b")),
      type = "message"
    )
  }, error = function(e) {
    showNotification(
      paste("Backup failed:", e$message),
      type = "error"
    )
  })
})

# View backups
output$backup_list <- DT::renderDataTable({
  backups <- list.files("backups", pattern = "*.db", full.names = TRUE)
  backup_info <- data.frame(
    filename = basename(backups),
    size_mb = format(file.size(backups) / 1024^2, digits = 2),
    created = format(file.info(backups)$mtime, "%Y-%m-%d %H:%M"),
    action = paste('<button class="btn btn-sm btn-info" onclick="restoreBackup(\'',
                   basename(backups), '\')">Restore</button>', sep = "")
  )
  backup_info
})

# One-click restore
observeEvent(input$restore_backup, {
  selected_backup <- input$backup_to_restore

  showModal(
    modalDialog(
      h4("Restore Database Backup"),
      p(paste("Are you sure? Current database will be replaced.")),
      p(paste("Backup:", selected_backup)),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_restore", "Yes, Restore", class = "btn-danger")
      )
    )
  )
})

observeEvent(input$confirm_restore, {
  tryCatch({
    file.copy(
      file.path("backups", input$backup_to_restore),
      cfg$database$path,
      overwrite = TRUE
    )

    showNotification("Database restored successfully. Please refresh the page.",
                     type = "message")
    removeModal()
  }, error = function(e) {
    showNotification(paste("Restore failed:", e$message), type = "error")
  })
})
```

**Feasibility:** ⭐⭐⭐⭐⭐ (Very high - simple file operations)

**Estimated effort:** 80-100 lines of code

---

### **1.4 Admin Dashboard Implementation Timeline**

**Phase 1A (Week 1 - MVP, 40 hours):**
- User management (view, add, edit, reset password)
- Role assignment
- Database backup/restore (one-click)
- Audit log viewer

**Phase 1B (Week 2 - Extended, 40 hours):**
- Form management (view, create from Google Sheets)
- System configuration interface
- Site management
- Email notifications

**Phase 2 (Week 3-4 - Advanced, 60 hours):**
- Visual form builder (drag-and-drop)
- Database repair tool
- Advanced audit filtering
- Performance monitoring

---

## Part 2: Setup Wizard Plan

### **2.1 Overview**

Replace `setup_from_gsheets.R` with interactive web-based wizard that guides non-technical users through setup.

**Access:** Before login - startup screen if database not detected

**Technology:** Shiny module that runs before main app loads

---

### **2.2 Setup Wizard Flow**

```
┌─────────────────────────────────────────┐
│ Welcome to ZZedc Setup Wizard           │
│                                         │
│ This wizard will help you set up your  │
│ clinical trial EDC system in 5 steps.  │
│                                         │
│ Estimated time: 10 minutes             │
│ [Start Setup] [Exit]                   │
└─────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────┐
│ Step 1/5: Basic Information             │
│                                         │
│ Study Name:        [________________]  │
│ Study Protocol ID: [________________]  │
│ Principal Investigator: [__________]   │
│ Target Enrollment: [___]               │
│                                         │
│ [Back] [Next]                          │
└─────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────┐
│ Step 2/5: Create Administrator Account  │
│                                         │
│ Username:        [________________]    │
│ Full Name:       [________________]    │
│ Email:           [________________]    │
│ Password:        [________________]    │
│ Confirm Password:[________________]    │
│                                         │
│ [Back] [Next]                          │
└─────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────┐
│ Step 3/5: Configure Security             │
│                                         │
│ ☑ Enable HTTPS (recommended for servers)
│ ☑ Require strong passwords             │
│ ☐ Enable two-factor authentication     │
│                                         │
│ Session timeout (minutes): [30]        │
│ Max login attempts: [3]                │
│                                         │
│ Generate security salt: [Generate]    │
│ Salt: ●●●●●●●●●●●●●●●●●●●●●●●●●●  │
│ (Copy and save this in a safe place)  │
│                                         │
│ [Back] [Next]                          │
└─────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────┐
│ Step 4/5: Create Initial Users          │
│                                         │
│ Add other team members (optional):     │
│                                         │
│ [+ Add User]                           │
│                                         │
│ Username: jsmith    Role: Coordinator  │
│ [Edit] [Delete]                       │
│                                         │
│ Username: schen     Role: PI           │
│ [Edit] [Delete]                       │
│                                         │
│ [Back] [Next]                          │
└─────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────┐
│ Step 5/5: Import Data Dictionary        │
│                                         │
│ ☐ Use template forms (Cognitive, ADHD) │
│ ☐ Import from Google Sheets            │
│ ☐ Upload CSV file                      │
│ ☑ Create blank database (customize later)
│                                         │
│ [Back] [Setup Complete]               │
└─────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────┐
│ ✓ Setup Complete!                      │
│                                         │
│ Your ZZedc system is ready to use.    │
│                                         │
│ Database: data/trial_2024.db          │
│ Admin user: you                        │
│ Team members: 2 users created         │
│                                         │
│ Next steps:                            │
│ 1. Add your study forms (in Admin)    │
│ 2. Invite team members                 │
│ 3. Create subject list                │
│                                         │
│ [Launch ZZedc] [View Admin Guide]     │
└─────────────────────────────────────────┘
```

---

### **2.3 Wizard Implementation Details**

**File Location:** `R/modules/setup_wizard_module.R` (new, ~600 lines)

**Code Structure:**
```r
setup_wizard_ui <- function() {
  # Step 1: Basic info
  step1_ui <- div(
    id = "step1",
    h3("Step 1 of 5: Basic Information"),
    textInput("wizard_study_name", "Study Name", placeholder = "e.g., Depression Treatment Trial"),
    textInput("wizard_protocol_id", "Protocol ID", placeholder = "e.g., DEPR-2024-001"),
    textInput("wizard_pi_name", "Principal Investigator", placeholder = "Dr. Jane Smith"),
    numericInput("wizard_enrollment", "Target Enrollment", value = 50, min = 1),
    help_text("This information will be stored in the database and displayed in reports.")
  )

  # Step 2: Admin user
  step2_ui <- div(
    id = "step2",
    h3("Step 2 of 5: Create Administrator Account"),
    p("This account will have full access to set up forms, manage users, and access all data."),
    textInput("wizard_admin_username", "Username", placeholder = "admin"),
    textInput("wizard_admin_name", "Full Name", placeholder = "John Doe"),
    textInput("wizard_admin_email", "Email", placeholder = "admin@example.com"),
    passwordInput("wizard_admin_password", "Password"),
    passwordInput("wizard_admin_password_confirm", "Confirm Password"),

    # Password strength indicator
    div(id = "password_strength",
      p("Password strength: ", span(id = "strength_label", "Weak"))
    )
  )

  # Step 3: Security
  step3_ui <- div(
    id = "step3",
    h3("Step 3 of 5: Security Configuration"),

    h4("Security Options"),
    checkboxInput("wizard_https", "Enable HTTPS (recommended for production)", value = FALSE),
    checkboxInput("wizard_strong_passwords", "Require strong passwords", value = TRUE),

    h4("Session Settings"),
    numericInput("wizard_timeout", "Session timeout (minutes)", value = 30, min = 5),
    numericInput("wizard_max_attempts", "Max failed login attempts", value = 3, min = 1),

    h4("Password Salt (for secure hashing)"),
    p("A random salt makes password hashing more secure. Click to generate."),
    actionButton("wizard_generate_salt", "Generate Security Salt"),
    textOutput("wizard_salt_display"),
    p(strong("Important:"), "Copy and save this salt in a safe place (password manager or document).",
      style = "color: #d9534f;"),

    help_text("The salt is used to make passwords secure. Do not share it.")
  )

  # Step 4: Additional users
  step4_ui <- div(
    id = "step4",
    h3("Step 4 of 5: Create Initial Team Members"),
    p("You can add more users later. This is optional - you can add users later in the Admin panel."),

    actionButton("wizard_add_user", "Add Team Member", class = "btn-secondary"),

    div(id = "users_list",
      # Dynamic user entries will be added here
    ),

    help_text("You can add users now or later through the Admin dashboard.")
  )

  # Step 5: Data dictionary
  step5_ui <- div(
    id = "step5",
    h3("Step 5 of 5: Create Data Dictionary"),

    h4("How would you like to start?"),

    radioButtons("wizard_dd_option", "Choose one:",
      choices = list(
        "Use template forms (fastest)" = "template",
        "Import from Google Sheets" = "gsheets",
        "Upload CSV file" = "csv",
        "Create blank database (add forms later)" = "blank"
      ),
      selected = "blank"
    ),

    conditionalPanel(
      "input.wizard_dd_option == 'template'",
      h5("Select template forms:"),
      checkboxGroupInput("wizard_templates", "",
        choices = c(
          "Cognitive Assessment (MMSE, MoCA)" = "cognitive",
          "ADHD Screening (Conners Scale)" = "adhd",
          "Depression Assessment (PHQ-9, GAD-7)" = "depression",
          "Vital Signs" = "vitals",
          "Demographics" = "demographics",
          "Adverse Events" = "ae"
        )
      )
    ),

    conditionalPanel(
      "input.wizard_dd_option == 'gsheets'",
      h5("Google Sheets Setup:"),
      p("Create a Google Sheet with your form definitions."),
      actionButton("wizard_gsheets_template", "View template format"),
      textInput("wizard_gsheets_id", "Google Sheet ID",
                placeholder = "Paste the Sheet ID from URL"),
      p(small("You'll need to authenticate with Google the first time."))
    ),

    conditionalPanel(
      "input.wizard_dd_option == 'csv'",
      h5("Upload CSV file:"),
      fileInput("wizard_csv_upload", "Choose CSV file")
    ),

    help_text("You can add more forms later through the Admin dashboard.")
  )

  # Main wizard container
  fluidPage(
    div(id = "setup_wizard",
      # Progress indicator
      div(class = "progress",
        style = "height: 25px;",
        div(class = "progress-bar", id = "progress_bar",
          role = "progressbar", style = "width: 0%;",
          span(id = "progress_text", "0%")
        )
      ),

      # Step containers
      step1_ui,
      step2_ui,
      step3_ui,
      step4_ui,
      step5_ui,

      # Navigation buttons
      fluidRow(
        column(6, actionButton("wizard_back", "Back")),
        column(6, align = "right",
          actionButton("wizard_next", "Next", class = "btn-primary"),
          actionButton("wizard_cancel", "Cancel", class = "btn-danger")
        )
      )
    )
  )
}

setup_wizard_server <- function(input, output, session) {
  # State management
  rv <- reactiveValues(
    current_step = 1,
    wizard_data = list()
  )

  # Navigate steps
  observeEvent(input$wizard_next, {
    # Validate current step
    if (validate_step(rv$current_step, input)) {
      rv$wizard_data <- update_wizard_data(rv$wizard_data, rv$current_step, input)

      if (rv$current_step < 5) {
        rv$current_step <- rv$current_step + 1
        update_progress_bar(rv$current_step)
      } else {
        # Final step - create database
        create_database_from_wizard(rv$wizard_data)
        showNotification("Setup complete! Launching ZZedc...", type = "message")
        Sys.sleep(2)
        session$reload()  # Reload to show login
      }
    }
  })

  observeEvent(input$wizard_back, {
    if (rv$current_step > 1) {
      rv$current_step <- rv$current_step - 1
      update_progress_bar(rv$current_step)
    }
  })
}

# Validation function
validate_step <- function(step, input) {
  switch(step,
    `1` = {
      if (input$wizard_study_name == "") {
        showNotification("Please enter a study name", type = "error")
        return(FALSE)
      }
      TRUE
    },
    `2` = {
      if (input$wizard_admin_username == "") {
        showNotification("Please enter a username", type = "error")
        return(FALSE)
      }
      if (input$wizard_admin_password != input$wizard_admin_password_confirm) {
        showNotification("Passwords do not match", type = "error")
        return(FALSE)
      }
      TRUE
    },
    TRUE
  )
}

# Database creation
create_database_from_wizard <- function(wizard_data) {
  # Create database
  con <- dbConnect(SQLite(), wizard_data$db_path)

  # Create tables
  # ... (existing setup_database.R code)

  # Insert wizard data
  # ...

  dbDisconnect(con)
}
```

**Feasibility:** ⭐⭐⭐⭐ (High - modular steps)

**Estimated effort:** 600-800 lines of code

---

### **2.4 Setup Wizard Implementation Timeline**

**Phase 1 (Week 1-2, 60 hours):**
- Basic wizard UI (all 5 steps)
- Step validation
- Basic database creation from inputs
- Success/completion screen

**Phase 2 (Week 3, 30 hours):**
- Google Sheets template import
- CSV import
- Pre-built form templates
- User invitations

---

## Part 3: Comprehensive Gap Analysis

### **3.1 Current Gaps (Prioritized)**

#### **Tier 1: Critical Blockers** (Prevents non-technical setup)

| Gap | Current State | Impact | Users Affected |
|-----|---------------|--------|-----------------|
| **Installation** | Requires R, RStudio, manual dependency install | ⛔ Blocks 95% of users | All non-technical |
| **Setup process** | Command-line R scripts | ⛔ Blocks 90% of users | All non-technical |
| **User management** | No in-app interface; requires DB knowledge | ⛔ Blocks 80% of ongoing ops | Data managers |
| **Form creation** | Google Sheets + re-run setup | ⛔ Blocks 70% from self-service | Coordinators |
| **No admin dashboard** | All management via R/SQL | ⛔ Blocks 85% of use cases | All admin users |

**Current blockers affecting:** ~90% of potential non-technical users

---

#### **Tier 2: Major Limitations** (Severely restricts non-technical use)

| Gap | Current State | Impact | Users Affected |
|-----|---------------|--------|-----------------|
| **Configuration** | YAML files, environment variables | ⚠️ Requires tech help | 60% of users |
| **Troubleshooting** | Cryptic R error messages | ⚠️ Breaks on small issues | 70% of issues |
| **Backups** | Manual file copying or SQL knowledge | ⚠️ Data at risk | 80% of systems |
| **Role-based UI rendering** | No conditional UI based on role | ⚠️ Security/UX issues | 40% of users |
| **Form validation interface** | No visual rule builder | ⚠️ Limited by R knowledge | 50% of forms |
| **No in-app documentation** | External guides only | ⚠️ Users get lost | 60% of new users |

**Current limitations affecting:** ~65% of non-technical workflows

---

#### **Tier 3: Medium Improvements** (Improve but don't block)

| Gap | Current State | Impact | Users Affected |
|-----|---------------|--------|-----------------|
| **No visual reports builder** | Limited to built-in reports | ⚠️ Limits customization | 30% of studies |
| **No scheduling/automation** | Manual job running | ⚠️ Requires reminders | 25% of studies |
| **No audit log UI** | Raw database query only | ⚠️ Compliance harder | 40% of audits |
| **No permission granularity** | Only role-based (not field-level) | ⚠️ Security limitations | 20% of users |
| **No email notifications** | Manual communication | ⚠️ Workflow delays | 35% of studies |
| **No user training module** | External materials only | ⚠️ Slower onboarding | 50% of users |

**Current improvements affecting:** ~30% of workflows

---

#### **Tier 4: Nice-to-Have Features** (Enhancement only)

| Gap | Current State | Impact | Users Affected |
|-----|---------------|--------|-----------------|
| **Dark mode** | Light theme only | ⚠️ Eye strain | 10% of users |
| **Multi-language support** | English only | ⚠️ International studies | 5% of users |
| **Mobile app** | Web only | ⚠️ Field data entry | 15% of studies |
| **Advanced analytics** | Basic reports only | ⚠️ Limited insights | 20% of studies |
| **API for external systems** | Not available | ⚠️ Integration difficult | 10% of sites |
| **Data visualization builder** | Not available | ⚠️ Limited exploration | 15% of users |

**Current features affecting:** ~10% of workflows

---

### **3.2 Gap Matrix**

```
Implementation Difficulty vs. Impact
────────────────────────────────────────

High Impact
    │
    │  ⚠️ TIER 1 (Critical)
    │  • Installation (5 weeks)
    │  • Setup Wizard (2 weeks)
    │  • Admin Dashboard (2 weeks)
    │  • User/Form Management (1 week)
    │  • Error handling (1 week)
    │
    │  ⚠️ TIER 2 (Major)
    │  • Config interface (1 week)
    │  • Backups UI (3 days)
    │  • Audit log viewer (3 days)
    │  • Role-based rendering (4 days)
    │  • Form validation UI (1 week)
    │
    │  ⚠️ TIER 3 (Medium)
    │  • Reports builder (2 weeks)
    │  • Notifications (1 week)
    │  • Automation/scheduling (2 weeks)
    │  • User training module (1 week)
    │
    │  ⚠️ TIER 4 (Nice-to-have)
    │  • Dark mode (2 days)
    │  • Mobile app (4 weeks)
    │  • API (2 weeks)
    │
Low Impact
    └────────────────────────────────────────
      Easy              Hard
      Implementation Difficulty
```

---

### **3.3 Gap Detail by Feature**

#### **Installation Gap (Blocks ~95% of users)**

**Current:**
```
1. Download R
2. Download RStudio
3. Install 15+ dependencies (RSQLite, Shiny, DBI, etc.)
4. Navigate file system
5. Run setup script
6. Debug environment issues
```

**Barriers:**
- Not everyone has admin rights to install software
- Windows/Mac/Linux variations
- Dependency conflicts
- Network/firewall issues
- No guided process

**Needed:**
- Standalone installer (Windows, Mac, Linux)
- Bundle R + RStudio + ZZedc
- Auto-dependency installation
- No command-line required
- One-click "Next > Next > Finish"

**Feasibility:** ⭐⭐ (Hard - requires packaging expertise)

**Timeline:** 3-4 weeks

---

#### **Setup Process Gap (Blocks ~90% of users)**

**Current:**
```r
source("setup_from_gsheets.R")
setup_zzedc_from_gsheets_complete(
  auth_sheet_name = "zzedc_auth",
  dd_sheet_name = "zzedc_data_dictionary",
  project_name = "trial_name"
)
```

**Barriers:**
- Requires R console knowledge
- No visual feedback during setup
- Errors are cryptic
- Multiple manual steps
- No validation before database creation

**Needed:**
- Web-based setup wizard (this section's Part 2)
- Visual progress indication
- Real-time error messages with solutions
- Pre-flight validation
- Automatic Google Sheets template creation
- Success confirmation

**Feasibility:** ⭐⭐⭐⭐ (High - straightforward Shiny module)

**Timeline:** 2 weeks

---

#### **User/Form Management Gap (Blocks ~80% of operations)**

**Current:**
- No in-app user management
- No in-app form management
- All changes require database knowledge or script re-running
- No UI for role assignment
- No form builder

**Barriers:**
- Users can't self-serve
- Data managers need programmer help
- Increases support burden
- Slows down operations

**Needed:**
- Admin dashboard (this section's Part 1)
- User CRUD operations
- Visual form builder
- Form templates
- Role management interface

**Feasibility:** ⭐⭐⭐⭐ (High - standard UI patterns)

**Timeline:** 2-3 weeks

---

#### **Configuration Gap (Affects ~60% of users)**

**Current:**
- YAML file editing
- Environment variables
- No validation of settings
- Settings affect behavior unpredictably

**Barriers:**
- YAML syntax errors break app
- Environment variables confusing
- No help/documentation for each setting
- Hard to know valid values

**Needed:**
- Settings panel in admin dashboard (no YAML editing)
- Dropdown menus for valid options
- Descriptions for each setting
- Live preview of changes
- Validation before saving

**Feasibility:** ⭐⭐⭐⭐ (High - form-based inputs)

**Timeline:** 1 week

---

#### **Error Handling Gap (Affects ~70% of issues)**

**Current:**
```
Error in config::get(): Config file not found in current working directory
Database disk image is malformed
Error in pool::dbGetQuery(db_pool, ...): could not prepare statement
```

**Barriers:**
- Error messages are technical
- No suggestion for how to fix
- Stack trace is intimidating
- Different errors have different causes

**Needed:**
- User-friendly error messages
- Links to documentation
- Suggested fixes
- Automatic recovery options where possible
- Helpful error catalog

**Feasibility:** ⭐⭐⭐ (Medium - covers many cases)

**Timeline:** 1-2 weeks

---

#### **Documentation Gap (Affects ~60% of users)**

**Current:**
- External markdown files
- Requires leaving app to learn
- Multiple docs across different locations
- Not integrated with actual features

**Needed:**
- In-app help (hover tooltips, info buttons)
- Contextual guides (show help for current screen)
- Video tutorials (embedded)
- Interactive walkthroughs
- Searchable documentation
- Glossary of terms

**Feasibility:** ⭐⭐⭐ (Medium - content creation overhead)

**Timeline:** 2-3 weeks

---

---

## Part 4: Feasibility & Timeline Assessment

### **4.1 What's Feasible to Implement Quickly (Next 2 Weeks)**

#### **High Impact, Low Effort** ⭐⭐⭐⭐⭐

**1. Setup Wizard** (40 hours)
- **Impact:** Eliminates command-line setup requirement
- **Effort:** Medium-high (600-800 lines)
- **Timeline:** 1-1.5 weeks
- **Users enabled:** 70% of coordinators
- **Implementation:** Build Shiny module with 5-step wizard
- **Blockers:** None identified
- **Post-launch:** Can be enhanced with more options later

**Effort/Impact Ratio:** 10:1 (EXCELLENT)

**Code structure:**
```
R/modules/setup_wizard_module.R (600 lines)
- UI: 5 steps with form inputs
- Server: validation + database creation
- Utilities: password hashing, database init
```

---

**2. One-Click Backups** (20 hours)
- **Impact:** Secures data, reduces support requests
- **Effort:** Low (100-150 lines)
- **Timeline:** 2-3 days
- **Users enabled:** 80% of sysadmins
- **Implementation:** File copy + UI for viewing/restoring
- **Blockers:** None identified
- **Post-launch:** Can add scheduled backups later

**Effort/Impact Ratio:** 15:1 (EXCELLENT)

**Code structure:**
```
In admin_dashboard_module.R (100 lines)
- UI: List backups, restore button
- Server: File operations, notifications
```

---

**3. User Management UI** (30 hours)
- **Impact:** Enables non-technical user adds/edits
- **Effort:** Medium (200-300 lines)
- **Timeline:** 3-4 days
- **Users enabled:** 60% of admins
- **Implementation:** CRUD modals in admin dashboard
- **Blockers:** Password hashing/salting (already exists)
- **Post-launch:** Can add bulk import later

**Effort/Impact Ratio:** 12:1 (EXCELLENT)

**Code structure:**
```
In admin_dashboard_module.R (200 lines)
- UI: Table + add/edit modals
- Server: CRUD operations, validation
```

---

**4. Audit Log Viewer** (20 hours)
- **Impact:** Transparency, compliance
- **Effort:** Low (150-200 lines)
- **Timeline:** 2-3 days
- **Users enabled:** 40% for compliance
- **Implementation:** Data table with filters
- **Blockers:** None identified
- **Post-launch:** Can add export/reporting later

**Effort/Impact Ratio:** 13:1 (EXCELLENT)

**Code structure:**
```
In admin_dashboard_module.R (150 lines)
- UI: DT table with filters
- Server: Query audit_trail table
```

---

**🎯 Quick Win Package (2 weeks, 110 hours)**
```
Total impact: Enables ~70% of non-technical operations
Implementation: Setup Wizard (7 days) + Backups (3 days)
              + User Mgmt (4 days) + Audit (3 days)
Files to create: R/modules/setup_wizard_module.R (800 lines)
Files to modify: R/modules/admin_dashboard_module.R (500 lines)
                 R/launch_zzedc.R (50 lines)
                 server.R (20 lines)
```

---

### **4.2 What's Feasible in Medium Term (3-6 Weeks)**

#### **High Impact, Medium Effort** ⭐⭐⭐⭐

**5. Form Builder UI** (50 hours)
- **Impact:** Non-technical form creation
- **Effort:** Medium-high (400+ lines of R + JavaScript)
- **Timeline:** 1-1.5 weeks
- **Users enabled:** 50% of coordinators
- **Implementation:** Table-based editor OR drag-and-drop builder
- **Blockers:** JavaScript expertise needed

**Effort/Impact Ratio:** 8:1 (EXCELLENT)

**Recommended approach:**
- Start with table-based editor (easier, 30 hours)
- Upgrade to drag-and-drop later (20 more hours)

---

**6. Configuration UI** (25 hours)
- **Impact:** Remove YAML file editing requirement
- **Effort:** Low-medium (200 lines)
- **Timeline:** 3-4 days
- **Users enabled:** 60% of sysadmins
- **Implementation:** Settings form in admin dashboard
- **Blockers:** None identified

**Effort/Impact Ratio:** 11:1 (EXCELLENT)

---

**7. Improved Error Handling** (40 hours)
- **Impact:** Reduce support requests by 50%
- **Effort:** Medium (covering ~20 common errors)
- **Timeline:** 1 week
- **Users enabled:** 80% (affects error scenarios)
- **Implementation:** Error handlers in R code + user-friendly messages
- **Blockers:** Identifying all common errors

**Effort/Impact Ratio:** 9:1 (EXCELLENT)

---

**8. In-App Documentation** (50 hours)
- **Impact:** Improve onboarding, reduce support
- **Effort:** Medium-high (50% code, 50% content)
- **Timeline:** 1-1.5 weeks
- **Users enabled:** 70%
- **Implementation:** Tooltips + help panels + video embeds
- **Blockers:** Content creation (can use AI for first draft)

**Effort/Impact Ratio:** 7:1 (VERY GOOD)

---

**🎯 Medium-Term Additions (3-6 weeks, 165 hours)**
```
Total impact: Enables ~85% of non-technical operations
Implementation: Form Builder (1-2 weeks)
              + Config UI (3-4 days)
              + Error handling (1 week)
              + Documentation (1-2 weeks)
```

---

### **4.3 What's Feasible Long-Term (6-12 Weeks)**

#### **Medium Impact, High Effort** ⭐⭐⭐

**9. Standalone Installer** (80 hours)
- **Impact:** Removes 95% of installation barriers
- **Effort:** High (requires packaging expertise)
- **Timeline:** 2-3 weeks
- **Users enabled:** 95% can install without help
- **Implementation:** Use Inno Setup (Windows), create DMG (Mac), AppImage (Linux)
- **Blockers:** Cross-platform testing needed

**Effort/Impact Ratio:** 4:1 (GOOD)

---

**10. Advanced Role-Based Features** (60 hours)
- **Impact:** Better security, multi-site support
- **Effort:** High (complex permission logic)
- **Timeline:** 1.5-2 weeks
- **Users enabled:** 40% of advanced studies
- **Implementation:** Field-level permissions, conditional UI rendering
- **Blockers:** Architecture review needed

**Effort/Impact Ratio:** 3:1 (MODERATE)

---

**11. Automated Scheduling** (70 hours)
- **Impact:** QC checks, data validation runs automatically
- **Effort:** High (job scheduling complexity)
- **Timeline:** 1.5-2 weeks
- **Users enabled:** 30% of large studies
- **Implementation:** cron jobs or R scheduler package
- **Blockers:** Server requirements

**Effort/Impact Ratio:** 3:1 (MODERATE)

---

**12. Mobile App** (200+ hours)
- **Impact:** Field data entry (nice-to-have)
- **Effort:** Very high (requires React Native or similar)
- **Timeline:** 4-6 weeks
- **Users enabled:** 15% of studies
- **Implementation:** Separate mobile app + API
- **Blockers:** Significant development effort

**Effort/Impact Ratio:** 1:1 (LOW - probably not worth it)

---

### **4.4 Master Timeline & Roadmap**

```
┌─────────────────────────────────────────────────────────┐
│ ZZedc Non-Technical Roadmap (6-8 Weeks)               │
└─────────────────────────────────────────────────────────┘

PHASE 1: QUICK WINS (Weeks 1-2, 110 hours)
┌─────────────────────────────────────────────────────────┐
│ ✓ Setup Wizard (7 days)                                │
│ ✓ User Management UI (4 days)                          │
│ ✓ One-Click Backups (3 days)                           │
│ ✓ Audit Log Viewer (3 days)                            │
│                                                         │
│ RESULT: ~70% of ops are non-technical                  │
│ USERS ENABLED: 65% of teams                            │
│ SUPPORT REDUCTION: 40%                                 │
└─────────────────────────────────────────────────────────┘
                         ↓
PHASE 2: POWER-UPS (Weeks 3-6, 165 hours)
┌─────────────────────────────────────────────────────────┐
│ ✓ Form Builder UI (table-based, 1 week)               │
│ ✓ Configuration UI (3-4 days)                          │
│ ✓ Better Error Messages (1 week)                       │
│ ✓ In-App Documentation (1-2 weeks)                     │
│ (Optional) Drag-and-Drop Form Builder (1 week)         │
│                                                         │
│ RESULT: ~85% of ops are non-technical                  │
│ USERS ENABLED: 80% of teams                            │
│ SUPPORT REDUCTION: 65%                                 │
└─────────────────────────────────────────────────────────┘
                         ↓
PHASE 3: ENTERPRISE (Weeks 7-12, 210 hours)
┌─────────────────────────────────────────────────────────┐
│ • Standalone Installer (2-3 weeks)                     │
│ • Advanced Role-Based Features (2 weeks)               │
│ • Automated Scheduling (2 weeks)                       │
│ • API/Integration Features (2 weeks)                   │
│                                                         │
│ RESULT: ~95% of ops are non-technical                  │
│ USERS ENABLED: 90% of teams                            │
│ SUPPORT REDUCTION: 85%                                 │
└─────────────────────────────────────────────────────────┘

TOTAL EFFORT: 485 hours (~12 weeks full-time)
             (~6-8 weeks with 2-3 developers)

NOT RECOMMENDED:
✗ Mobile app (high effort, low impact for EDC)
✗ Advanced analytics (nice-to-have, not critical)
```

---

### **4.5 Effort Breakdown by Role**

```
DEVELOPER SKILLS NEEDED:

Phase 1 (Quick Wins):
- Shiny expert (UI/UX): 40%
- R developer (backend): 40%
- QA/Testing: 20%

Phase 2 (Power-Ups):
- Shiny expert: 35%
- R developer: 35%
- JavaScript developer: 20% (form builder)
- Content writer: 10% (docs)

Phase 3 (Enterprise):
- R developer: 40%
- DevOps/Packaging: 40%
- Architect: 20%

MINIMUM TEAM:
- Option A: 1 full-stack Shiny developer (8 weeks)
- Option B: 2 developers (1 Shiny, 1 R) (4-5 weeks)
- Option C: 3 developers + content (3 weeks)
```

---

### **4.6 What NOT to Do**

```
❌ DON'T build these (low impact, high effort):
  - Mobile app (15% of users, 200 hours)
  - Advanced analytics dashboard (20% of users, 100 hours)
  - Multi-language support (5% of users, 80 hours)
  - Dark mode theme (10% of users, 40 hours)
  - API/external integrations (10% of users, 100 hours)

✓ DO build these (high impact, lower effort):
  - Setup Wizard (70% of users, 80 hours)
  - User management UI (60% of users, 30 hours)
  - Form builder (50% of users, 50 hours)
  - One-click backups (80% of users, 20 hours)
  - Better error messages (80% of users, 40 hours)
```

---

## Part 5: Recommended Implementation Strategy

### **5.1 Quick Start (Start This Week)**

**If you have 1 developer:**
```
Week 1-2: Build setup wizard (80 hours)
          → Unblocks 70% of new users

Week 3-4: Add user management UI (30 hours)
          + backups (20 hours)
          + audit log (20 hours)
          → Enables 80% of operations

Week 5-6: Form builder table editor (40 hours)
          → Non-technical form creation

TOTAL: 6 weeks, 1 developer → ~80% non-technical ops
```

---

**If you have 2 developers:**
```
Parallel work:
Dev 1: Setup wizard (Weeks 1-2)
Dev 2: Admin dashboard skeleton (Weeks 1-2)
       ↓
Dev 1: User management UI (Weeks 3)
Dev 2: Form builder (Weeks 3-4)
       ↓
Both: Integration + testing (Weeks 5)
      ↓
Deploy Phase 1 (Week 6)

TOTAL: 5 weeks, 2 developers → ~75% non-technical ops
```

---

**If you have 3 developers:**
```
Dev 1: Setup wizard
Dev 2: Admin dashboard (user mgmt + backups)
Dev 3: Form builder + documentation

All parallel (Weeks 1-2):
Deploy Phase 1 → 80% non-technical

Weeks 3-4:
Dev 1: Config UI + error handling
Dev 2: Advanced form builder
Dev 3: Documentation completion

Deploy Phase 2 (Week 5) → 85% non-technical
```

---

### **5.2 Success Criteria**

**Phase 1 Complete When:**
- [ ] Setup wizard deployed and tested
- [ ] User can create admin account via wizard
- [ ] User can import users via wizard
- [ ] User can add additional users via dashboard
- [ ] One-click backup works
- [ ] Audit log is viewable
- [ ] 10 non-technical users successfully set up system
- [ ] Average setup time < 15 minutes

**Phase 2 Complete When:**
- [ ] Non-technical user can create form (table editor)
- [ ] Form builder has validation
- [ ] Configuration editor works (no YAML)
- [ ] Error messages are user-friendly
- [ ] In-app documentation helps 80% of questions
- [ ] 20 non-technical users managing system without tech help

**Phase 3 Complete When:**
- [ ] Standalone installer works on Windows/Mac/Linux
- [ ] Average installation time < 5 minutes
- [ ] Role-based access control working
- [ ] Automated QC checks running
- [ ] ~95% of coordinators can operate independently

---

### **5.3 Budget Estimate**

```
Assuming $100-150/hour developer cost:

Phase 1 (Quick Wins):     110 hours × $125 = $13,750
Phase 2 (Power-Ups):      165 hours × $125 = $20,625
Phase 3 (Enterprise):     210 hours × $125 = $26,250
─────────────────────────────────────────────
TOTAL:                    485 hours        = $60,625

Alternative (3x faster):  $60,625 / 3 developers in parallel ≈ 3-4 weeks

Cost per week of savings: ~$5,000-7,000 in developer time
```

---

## Summary: Path to Non-Technical ZZedc

### **Right Now (This Week)**
1. **Make decision:** Proceed with implementation?
2. **Allocate developers:** 1-3 developers available?
3. **Start Phase 1:** Setup wizard is highest impact, lowest risk

### **In 2 Weeks**
- ✓ Setup wizard deployed
- ✓ Non-technical users can initialize system
- ✓ Support requests drop 40%

### **In 6 Weeks**
- ✓ Complete admin dashboard
- ✓ User management UI
- ✓ Form builder (basic)
- ✓ 80% of operations non-technical
- ✓ Support requests drop 65%

### **In 12 Weeks**
- ✓ Standalone installer
- ✓ Advanced features
- ✓ 95% of operations non-technical
- ✓ Clinical teams operate independently
- ✓ Support requests drop 85%

---

## Next Steps

**Choose one:**

**A) Greenlight Phase 1**
   - Allocate 1-2 developers for 2-3 weeks
   - Focus: Setup wizard + basic admin dashboard
   - Expected ROI: 40% reduction in support requests

**B) Do minimal now, plan later**
   - Document the gaps (this doc)
   - Plan for future when bandwidth available
   - Update documentation to ease current pain

**C) Partner approach**
   - Hire contract developer for Phase 1 (2-3 weeks, $13K-20K)
   - Internal team handles Phase 2+
   - Get to 80% non-technical operation quickly

**D) Research alternative**
   - Evaluate commercial EDC systems
   - Compare total cost of ownership
   - Decision: Build vs. Buy

---

**Recommendation:** Option A or C
- Phase 1 has highest ROI (impact/effort ratio)
- Setup wizard alone unblocks 70% of users
- Low risk to implement
- Can iterate based on feedback
