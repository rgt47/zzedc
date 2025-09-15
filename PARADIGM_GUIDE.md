# ZZCOLLAB Paradigm Guide

**Three Research Workflows for Modern Science**

ZZCOLLAB supports three research paradigms, each optimized for different stages of the research lifecycle. This guide helps you choose the right paradigm for your project and understand what each provides.

## 📊 **Analysis Paradigm** (Default)
*"From raw data to insights"*

### When to Use
- **Data Science Projects**: Exploratory data analysis, statistical modeling, machine learning
- **Research Analytics**: Survey analysis, experimental data processing, longitudinal studies  
- **Business Analytics**: Market research, customer analysis, operational insights
- **Academic Research**: Quantitative analysis phase of research projects

### Project Structure
```
your-project/
├── data/
│   ├── raw/               # Original, unmodified datasets
│   └── processed/         # Clean, analysis-ready data
├── analysis/
│   ├── exploratory/       # Initial data exploration (EDA)
│   ├── modeling/          # Statistical models and ML pipelines
│   └── validation/        # Model validation and testing
├── outputs/
│   ├── figures/           # Publication-quality plots
│   └── tables/            # Summary statistics and results
├── reports/
│   └── dashboard/         # Interactive reports and dashboards
└── scripts/               # Working analysis scripts
```

### Key Features
- **Optimized for**: Data processing, visualization, statistical analysis
- **Primary Tools**: tidyverse, targets, plotly, DT, flexdashboard
- **Workflow**: Raw data → Processing → Analysis → Visualization → Reports
- **CI/CD Focus**: Data validation, analysis reproduction, report generation

### Best For
- PhD students analyzing dissertation data
- Data scientists building predictive models  
- Researchers conducting quantitative studies
- Analysts creating recurring reports

---

## 📄 **Manuscript Paradigm**
*"From analysis to publication"*

### When to Use
- **Academic Papers**: Journal articles, conference papers, dissertations
- **Research Reports**: Technical reports, white papers, policy briefs
- **Computational Research**: Papers with integrated code and reproducible results
- **Collaborative Writing**: Multi-author manuscripts with version control

### Project Structure
```
your-manuscript/
├── R/                     # Manuscript-related functions
│   ├── analysis.R        # Statistical analysis functions
│   ├── plotting.R        # Custom plotting functions
│   └── simulations.R     # Simulation and modeling code
├── tests/testthat/        # Unit tests for R functions
├── manuscript/
│   ├── main.Rmd          # Primary manuscript file
│   ├── sections/         # Individual manuscript sections
│   ├── figures/          # Generated figures for paper
│   └── tables/           # Formatted tables
├── analysis/reproduce/    # Complete reproduction scripts
│   ├── 01_data_prep.R    # Data preparation
│   ├── 02_analysis.R     # Main analysis
│   ├── 03_figures.R      # Figure generation
│   └── run_all.R         # Master reproduction script
├── data/processed/        # Analysis-ready datasets
└── submission/
    ├── journal-format/    # Journal-specific formatting
    └── preprint/          # Preprint version
```

### Key Features
- **Optimized for**: Academic writing with integrated R code and testing
- **Primary Tools**: rmarkdown, bookdown, papaja, devtools, testthat, RefManageR
- **Workflow**: Analysis → Writing → Testing → Reproduction → Submission
- **CI/CD Focus**: Manuscript rendering, citation checking, reproduction validation

### Best For
- Academic researchers writing journal articles
- Graduate students writing thesis chapters
- Scientists publishing computational research
- Teams collaborating on technical reports

---

## 📦 **Package Paradigm**
*"From code to software"*

### When to Use
- **R Package Development**: Creating reusable R packages for CRAN or GitHub
- **Research Software**: Tools and methods for other researchers
- **Internal Tools**: Organization-specific analysis packages
- **Method Implementation**: Statistical methods, algorithms, data processing tools

### Project Structure
```
your-package/
├── R/                     # Package functions (exported to users)
├── tests/testthat/        # Comprehensive unit tests
├── man/                   # Documentation (auto-generated)
├── vignettes/             # Long-form tutorials and examples
├── inst/examples/         # Example datasets and scripts
├── data/                  # Package datasets (.rda files)
├── data-raw/              # Scripts to create package data
└── pkgdown/               # Website configuration
```

### Key Features
- **Optimized for**: Software development with rigorous testing and documentation
- **Primary Tools**: devtools, roxygen2, testthat, pkgdown, covr, lintr
- **Workflow**: Code → Document → Test → Check → Release
- **CI/CD Focus**: R CMD check, test coverage, documentation building, CRAN submission

### Best For
- R developers creating packages for community use
- Researchers packaging methods for publication
- Teams building internal analysis tools
- Scientists contributing to open source projects

---

## 🎯 **Choosing Your Paradigm**

### Quick Decision Tree

1. **What's your primary goal?**
   - 📊 **Analyze data** → Analysis paradigm
   - 📄 **Write a paper** → Manuscript paradigm  
   - 📦 **Build software** → Package paradigm

2. **What's your main output?**
   - 📊 **Reports, dashboards, insights** → Analysis
   - 📄 **Published papers, articles** → Manuscript
   - 📦 **R packages, software tools** → Package

3. **Who's your audience?**
   - 📊 **Stakeholders, decision makers** → Analysis
   - 📄 **Academic community, peer reviewers** → Manuscript
   - 📦 **Other developers, R users** → Package

### Common Research Lifecycle

Many projects progress through paradigms:

```
📊 Analysis → 📄 Manuscript → 📦 Package
```

1. **Analysis**: Explore data and develop methods
2. **Manuscript**: Write up findings for publication  
3. **Package**: Share tools with broader community

---

## 🚀 **Getting Started**

### Create Your Project

```bash
# Analysis project (default)
zzcollab

# Or explicitly specify paradigm
zzcollab --paradigm analysis
zzcollab -P analysis

# Manuscript project  
zzcollab --paradigm manuscript
zzcollab -P manuscript

# Package project
zzcollab --paradigm package  
zzcollab -P package
```

### Configuration

Set your default paradigm:

```bash
zzcollab config set paradigm analysis
zzcollab config set paradigm manuscript  
zzcollab config set paradigm package
```

Or in R:
```r
library(zzcollab)
set_config("paradigm", "manuscript")
```

---

## 💡 **Tips for Success**

### Analysis Paradigm
- Keep raw data immutable in `data/raw/`
- Use meaningful variable names and document data sources
- Create reproducible analysis scripts in `analysis/`
- Generate publication-ready figures in `outputs/figures/`

### Manuscript Paradigm  
- Write functions in `R/` and test them in `tests/`
- Keep reproduction scripts in `analysis/reproduce/` 
- Use version control for collaborative writing
- Automate figure and table generation

### Package Paradigm
- Follow R package conventions strictly
- Write comprehensive tests for all functions
- Document everything with roxygen2 comments
- Use semantic versioning for releases

---

## 🔄 **All Paradigms Include**

Regardless of paradigm, every ZZCOLLAB project includes:

- **Docker Integration**: Reproducible computational environment
- **GitHub Actions**: Automated testing and validation  
- **renv Management**: Dependency tracking and restoration
- **Team Collaboration**: Multi-developer workflows
- **Documentation**: Comprehensive project documentation
- **Quality Assurance**: Automated checks and validation

---

## 📚 **Learn More**

- **ZZCOLLAB Documentation**: Run `zzcollab --help`
- **Workflow Guidance**: Run `zzcollab --next-steps`
- **Configuration Help**: Run `zzcollab config --help`  
- **R Interface**: See `help(package = "zzcollab")` in R

Each paradigm is designed to support best practices in reproducible research while adapting to your specific workflow needs.