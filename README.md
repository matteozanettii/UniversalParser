# FSDA Table Interface & Autopilot
**The bridge between modern MATLAB Tables and the FSDA Toolbox.**

## Overview
This project provides a robust, Object-Oriented (OOP) interface to seamlessly use MATLAB `table` and `timetable` data types with the **Field Studies and Data Analysis (FSDA)** toolbox. It eliminates the need for manual data extraction, missing value handling, and variable mapping.

## Key Features
- **FSDAAutopilot**: A core engine that automatically handles `rmmissing`, variable extraction (X, Y, Groups), and type conversion.
- **Universal Parser**: A smart router that detects specialized "safe" wrappers or falls back to the Autopilot.
- **Self-Healing Methods**: Includes `safe_grpstatsFS` to handle edge cases (like `medcouple` errors) by providing robust statistical fallbacks.
- **Automatic Labeling**: Automatically injects Table variable names into FSDA plots for immediate clarity.

## Installation
1. Clone this repository.
2. Run `setup.m` in MATLAB to initialize the environment and paths.

## Quick Start
```matlab
% Initialize
setup;

% Create the Autopilot for your table
ap = FSDAAutopilot(myTable, struct('Y','TargetVar','X',["Pred1","Pred2"]));

% Execute any FSDA function directly
results = ap.exec('LXS');