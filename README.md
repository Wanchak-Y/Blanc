# BLANC

### A simple and elegant LaTeX editor for macOS.

BLANC is a native LaTeX editor for macOS, designed around a simple idea: writing LaTeX should focus on the document itself, rather than the tools around it.

BLANC combines a clean native interface, project management, LaTeX editing, compilation and PDF preview into a single workspace.

> **Current status: Early Development**

---

## Download

The easiest way to try BLANC is to download the latest release.

### Latest Release

**[Download BLANC for macOS](../../releases/latest)**

Download the `.dmg` file from the latest GitHub Release, open it, and drag **BLANC** into your Applications folder.

> BLANC is currently distributed as an early development version. Some features may still be incomplete or change in future releases.

---

## Features

### LaTeX Editor

* LaTeX syntax highlighting
* Line numbers
* Current-line highlighting
* Native macOS text editing experience
* Support for XeLaTeX
* Support for pdfLaTeX
* One-click compilation and PDF preview

### Project Management

* Create and manage `.tex` files
* Folder hierarchy
* Collapsible folders
* Drag and drop files between folders
* Tab-based document editing
* Context menus for files and folders
* Main document management

### PDF Preview

BLANC is designed around a simple workflow:

**Edit → Compile → Preview**

The source code and compiled PDF are kept within the same workspace, reducing the need to switch between different applications while writing.

---

## Package Composer

### Coming Soon

**Package Composer** is a planned companion tool for BLANC.

The goal is to provide a visual environment for creating and managing LaTeX packages without requiring users to manually organize every package file and configuration from scratch.

Planned features include:

* Package project management
* `.sty` package creation
* Package metadata management
* Dependency management
* LaTeX package structure generation
* Documentation generation
* Package preview and testing

**Status:** `Planned / Not yet available`

Package Composer is currently under design and has **not yet been released**.

---

## Design

BLANC is designed specifically for macOS.

The interface follows a restrained visual language, with an emphasis on typography, spacing, hierarchy and native macOS interaction patterns.

Rather than adding visual elements for decoration, BLANC attempts to keep the interface quiet enough that the document remains the focus.

---

## Feedback

BLANC is still in development, so feedback is particularly useful.

If you encounter a bug, have a feature request, or simply have an idea about how BLANC could be improved, please let me know.

### GitHub Issues

For bugs and feature requests:

**[Open an Issue](../../issues/new/choose)**

When reporting a bug, please include:

* macOS version
* BLANC version
* What you were doing
* What you expected to happen
* What actually happened
* Screenshots or error messages, if available

### Discussions

For general ideas, questions and suggestions:

**[Join GitHub Discussions](../../discussions)**

---

## Development

BLANC is written in **Swift** and developed for macOS using Apple's native development tools.

The project is currently under active development. APIs, interface details and internal architecture may change between releases.

If you would like to experiment with the source code, clone the repository and open the Xcode project.

```bash
git clone https://github.com/USERNAME/BLANC.git
cd BLANC
open BLANC.xcodeproj
```

---

## Roadmap

### BLANC

* [x] LaTeX editor
* [x] Syntax highlighting
* [x] Line numbers
* [x] PDF preview
* [x] XeLaTeX support
* [x] pdfLaTeX support
* [x] File management
* [x] Folder management
* [x] Tab management
* [ ] Improved error reporting
* [ ] Advanced project management
* [ ] Customizable editor settings
* [ ] More compilation engines
* [ ] Improved document navigation

### Package Composer

* [ ] Package project creation
* [ ] `.sty` generation
* [ ] Package metadata editor
* [ ] Dependency management
* [ ] Package documentation
* [ ] Package testing
* [ ] Package preview

The roadmap is subject to change as development continues.

---

## Requirements

* macOS
* Xcode, if building from source

The minimum supported macOS version may change during development.

Please check the release notes for the requirements of each version.

---

## License

Copyright © 2026 DAE Development.

See `LICENSE` for the terms under which this software is distributed.

---

## About

**BLANC** is developed by **DAE Development**.

The project is an attempt to build a LaTeX writing environment that is simple enough to disappear into the background while remaining powerful enough for serious document production.

**BLANC — Write in LaTeX.**
