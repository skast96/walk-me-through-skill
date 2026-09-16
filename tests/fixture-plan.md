# CSV Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a CSV export of the orders table to the admin dashboard.

**Architecture:** A pure formatting function turns order rows into CSV text. A new HTTP endpoint streams that text with a download header. A button in the dashboard calls the endpoint. Streaming was chosen over building the file in memory because the orders table has two million rows.

**Tech Stack:** Go 1.24, net/http, existing `orders` package, existing dashboard template.

**Spec:** none, this is a fixture.

## Global Constraints

- No new third party dependencies.
- CSV must open in Excel without a wizard, so use a UTF-8 byte order mark.
- Endpoint requires the existing admin session cookie.

---

### Task 1: CSV formatter

**Files:**
- Create: `orders/csv.go`
- Test: `orders/csv_test.go`

**Interfaces:**
- Produces: `func WriteCSV(w io.Writer, rows []Order) error`

- [ ] **Step 1: Write the failing test** for a two row input and one row with a comma in the customer name.
- [ ] **Step 2: Run the test** and see it fail.
- [ ] **Step 3: Implement WriteCSV** with encoding/csv and the byte order mark.
- [ ] **Step 4: Run the test** and see it pass.
- [ ] **Step 5: Commit.**

### Task 2: Export endpoint

**Files:**
- Create: `admin/export.go`
- Modify: `admin/routes.go`
- Test: `admin/export_test.go`

**Interfaces:**
- Consumes: `orders.WriteCSV`
- Produces: `GET /admin/orders.csv`

- [ ] **Step 1: Write the failing test** with httptest, asserting status 200, content type text/csv, and a Content-Disposition attachment header.
- [ ] **Step 2: Run the test** and see it fail.
- [ ] **Step 3: Implement the handler.** Iterate orders in batches of one thousand and write each batch through WriteCSV so memory stays flat.
- [ ] **Step 4: Run the test** and see it pass.
- [ ] **Step 5: Commit.**

### Task 3: Dashboard button

**Files:**
- Modify: `templates/admin/orders.html`

- [ ] **Step 1: Add a link** styled as a button pointing at `/admin/orders.csv`.
- [ ] **Step 2: Load the page** and click the button. A file downloads.
- [ ] **Step 3: Commit.**
