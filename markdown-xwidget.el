;;; markdown-xwidget.el --- Markdown preview with xwidgets  -*- lexical-binding: t; -*-

;; Author: Chris Clark <cfclrk@gmail.com>
;; Version: 0.1
;; Package-Requires: ((emacs "26.1") (markdown-mode "2.5") (f "0.20.0") (ht "2.4") (mustache "0.24"))
;; Keywords: convenience tools
;; URL: https://github.com/cfclrk/markdown-xwidget

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; See documentation at https://github.com/cfclrk/markdown-xwidget

;;; Code:

(require 'xwidget)
(require 'markdown-mode)
(require 'mustache)
(require 'ht)
(require 'f)

;;;; Variables

(defconst markdown-xwidget-directory
  (file-name-directory (if load-in-progress
                           load-file-name
                         (buffer-file-name)))
  "The package directory of markdown-xwidget.")

(defgroup markdown-xwidget nil
  "Markdown preview using xwidgets."
  :group 'markdown-xwidget
  :prefix "markdown-xwidget-")

(defcustom markdown-xwidget-github-theme
  (if (frame-parameter nil 'background-mode)
    "dark"
  "light")
  "The GitHub CSS theme to use."
  :type '(choice
          (const "light")
          (const "light-colorblind")
          (const "light-high-contrast")
          (const "light-tritanopia")
          (const "dark")
          (const "dark-dimmed")
          (const "dark-colorblind")
          (const "dark-high-contrast")
          (const "dark-tritanopia"))
  :group 'markdown-xwidget)

(defcustom markdown-xwidget-code-block-theme
  "github"
  "The highlight.js CSS theme to use in code blocks.
The highlight.js themes are defined here:
https://github.com/highlightjs/highlight.js/tree/main/src/styles"
  :type 'string)

(defcustom markdown-xwidget-mermaid-theme
  "default"
  "The mermaid theme to use in mermaid diagrams.
Mermaid themes are enumerated here:
https://mermaid-js.github.io/mermaid/#/theming?id=deployable-themes"
  :type '(choice
          (const "base")
          (const "forest")
          (const "dark")
          (const "default")
          (const "neutral"))
  :group 'markdown-xwidget)

(defcustom markdown-xwidget-command
  nil
  "An executable program to turn markdown into HTML.
If nil, the value of `markdown-command' will be used."
  :type '(string :tag "Shell command")
  :group 'markdown-xwidget)

(defvar markdown-xwidget-preview-mode nil
  "Sentinel variable for command `markdown-xwidget-preview-mode'.")

(defvar-local markdown-xwidget--xwidget-buffer nil
  "The xwidget buffer associated with this markdown buffer.")

(defvar-local markdown-xwidget--source-buffer nil
  "The markdown source buffer associated with this xwidget buffer.")

;;;; Functions

(defun markdown-xwidget--cleanup-source-buffer ()
  "Clean up the source buffer's reference to the xwidget buffer.
Disables preview mode if it was enabled."
  (when (and markdown-xwidget--source-buffer
             (buffer-live-p markdown-xwidget--source-buffer))
    (with-current-buffer markdown-xwidget--source-buffer
      (setq markdown-xwidget--xwidget-buffer nil)
      (when markdown-xwidget-preview-mode
        (markdown-xwidget-preview-mode -1)))))

(defun markdown-xwidget--kill-xwidget-buffer (buf)
  "Kill xwidget buffer BUF without confirmation prompts."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (remove-hook 'kill-buffer-hook #'markdown-xwidget--kill-buffer-hook t))
    (kill-buffer buf)))

(defun markdown-xwidget--kill-buffer-hook ()
  "Hook to run when xwidget buffer is killed externally.
Disables preview mode in the source buffer and closes the preview window."
  (let ((win (get-buffer-window (current-buffer))))
    (setq xwidget-webkit-last-session-buffer nil)
    (markdown-xwidget--cleanup-source-buffer)
    (when (and win (window-live-p win))
      (delete-window win))))

(defun markdown-xwidget-close-preview ()
  "Close the xwidget preview buffer and window without confirmation."
  (interactive)
  (let ((buf (current-buffer))
        (win (get-buffer-window (current-buffer))))
    (setq xwidget-webkit-last-session-buffer nil)
    (markdown-xwidget--cleanup-source-buffer)
    (markdown-xwidget--kill-xwidget-buffer buf)
    (when (and win (window-live-p win))
      (delete-window win))))

(defun markdown-xwidget-preview (file)
  "Preview FILE with xwidget-webkit.
To be used with `markdown-live-preview-window-function'."
  (let ((uri (format "file://%s" file))
        (source-buffer (current-buffer)))
    ;; If we already have our own xwidget buffer, reuse it
    (if (and markdown-xwidget--xwidget-buffer
             (buffer-live-p markdown-xwidget--xwidget-buffer))
        (with-current-buffer markdown-xwidget--xwidget-buffer
          (xwidget-webkit-goto-uri (xwidget-webkit-current-session) uri)
          markdown-xwidget--xwidget-buffer)
      ;; Otherwise create a new session, suppressing any prompts
      (let ((kill-buffer-query-functions nil))
        (xwidget-webkit-browse-url uri t)) ; t = new session
      (let ((xwidget-buffer xwidget-webkit-last-session-buffer))
        (setq markdown-xwidget--xwidget-buffer xwidget-buffer)
        (with-current-buffer xwidget-buffer
          (setq markdown-xwidget--source-buffer source-buffer)
          (add-hook 'kill-buffer-hook #'markdown-xwidget--kill-buffer-hook nil t)
          ;; Disable xwidget's kill confirmation for this buffer
          (setq-local kill-buffer-query-functions
                      (remq 'xwidget-kill-buffer-query-function
                            kill-buffer-query-functions))
          ;; Bind q to close preview properly (handle evil-mode if present)
          (if (bound-and-true-p evil-mode)
              (evil-local-set-key 'normal (kbd "q") #'markdown-xwidget-close-preview)
            (local-set-key (kbd "q") #'markdown-xwidget-close-preview)))
        xwidget-buffer))))

(defun markdown-xwidget-resource (rel-path)
  "Return the absolute path for REL-PATH.
REL-PATH is a path relative to the resources/ directory in this
project."
  (expand-file-name (f-join "resources/" rel-path) markdown-xwidget-directory))

(defun markdown-xwidget-github-css-path (theme-name)
  "Return the absolute path to the github THEME-NAME file."
  (markdown-xwidget-resource (concat "github_css/" theme-name ".css")))

(defun markdown-xwidget-highlightjs-css-path (theme-name)
  "Return the absolute path to the highlight.js THEME-NAME file.
Themes can be in highlight_css/ or highlight_css/base16/."
  (let ((root-path (markdown-xwidget-resource (concat "highlight_css/" theme-name ".css")))
        (base16-path (markdown-xwidget-resource (concat "highlight_css/base16/" theme-name ".css"))))
    (cond ((file-exists-p root-path) root-path)
          ((file-exists-p base16-path) base16-path)
          (t root-path))))

;;;; markdown-xwidgethtml-header-content

(defun markdown-xwidget-header-html (mermaid-theme)
  "Return header HTML with all js and MERMAID-THEME templated in.
Meant for use with `markdown-xtml-header-content'."
  (let ((context
         (ht ("highlight-js"  (markdown-xwidget-resource "highlight.min.js"))
             ("mermaid-js"    (markdown-xwidget-resource "mermaid.min.js"))
             ("mathjax-js"    (markdown-xwidget-resource "tex-mml-chtml.js"))
             ("mermaid-theme" mermaid-theme)))
        (html-template
         (f-read-text (markdown-xwidget-resource "header.html"))))

    ;; Render the HTML from a mustache template
    (mustache-render html-template context)))

;;;; Minor mode

(defvar markdown-xwidget--markdown-css-paths-original
  markdown-css-paths)
(defvar markdown-xwidget--markdown-command-original
  markdown-command)
(defvar markdown-xwidget--markdown-live-preview-window-function-original
  markdown-live-preview-window-function)
(defvar markdown-xwidget--markdown-xhtml-header-content-original
  markdown-xhtml-header-content)

(defun markdown-xwidget-preview-mode--enable ()
  "Enable `markdown-xwidget-preview-mode'.
This works by enabling `markdown-live-preview-mode' using
temporary values for a bunch of `markdown-mode' variables.

This function saves the original values for all relevant
`markdown-mode' variables, so that the original values can be
restored again when this mode is disabled."
  (let ((github-theme (markdown-xwidget-github-css-path
                       markdown-xwidget-github-theme))
        (code-block-theme (markdown-xwidget-highlightjs-css-path
                           markdown-xwidget-code-block-theme))
        (header-html (markdown-xwidget-header-html
                      markdown-xwidget-mermaid-theme))
        (command (or
                  markdown-xwidget-command
                  markdown-command)))

    (if (not (featurep 'xwidget-internal))
        (user-error "This Emacs does not support xwidgets!"))

    ;; Temporarily set markdown-css-paths
    (setq markdown-xwidget--markdown-css-paths-original
          markdown-css-paths)
    (setq markdown-css-paths (list github-theme code-block-theme))

    ;; Temporarily set markdown-command
    (setq markdown-xwidget--markdown-command-original
          markdown-command)
    (setq markdown-command command)

    ;; Temporarily set markdown-live-preview-window-function
    (setq markdown-xwidget--markdown-live-preview-window-function-original
          markdown-live-preview-window-function)
    (setq markdown-live-preview-window-function #'markdown-xwidget-preview)

    ;; Temporarily set markdown-xhtml-header-content
    (setq markdown-xwidget--markdown-xhtml-header-content-original
          markdown-xhtml-header-content)
    (setq markdown-xhtml-header-content header-html))

  (markdown-live-preview-mode 1))

(defun markdown-xwidget-preview-mode--disable ()
  "Disable `markdown-xwidget-preview-mode'.
This restores the original values for all the `markdown-mode'
variables that were set when this mode was enabled, and kills the
xwidget buffer if it still exists."
  (setq markdown-css-paths
        markdown-xwidget--markdown-css-paths-original)
  (setq markdown-command
        markdown-xwidget--markdown-command-original)
  (setq markdown-live-preview-window-function
        markdown-xwidget--markdown-live-preview-window-function-original)
  (setq markdown-xhtml-header-content
        markdown-xwidget--markdown-xhtml-header-content-original)
  ;; Kill the xwidget buffer if it exists
  (markdown-xwidget--kill-xwidget-buffer markdown-xwidget--xwidget-buffer)
  (setq markdown-xwidget--xwidget-buffer nil)
  ;; Clear stale global xwidget session reference
  (unless (buffer-live-p xwidget-webkit-last-session-buffer)
    (setq xwidget-webkit-last-session-buffer nil))
  (markdown-live-preview-mode -1))

;;;###autoload
(define-minor-mode markdown-xwidget-preview-mode
  "Enable previewing markdown files using xwidget-webkit.
Enabling this mode:

- temporarily sets many `markdown-mode' variables related to
  rendering/previewing
- turns on `markdown-live-preview-mode'

Disabling the mode turns off `markdown-live-preview-mode' and
restores the original values for all relevant `markdown-mode'
variables."
  :global nil
  :init-value nil
  (if markdown-xwidget-preview-mode
      (markdown-xwidget-preview-mode--enable)
    (markdown-xwidget-preview-mode--disable)))

(provide 'markdown-xwidget)
;;; markdown-xwidget.el ends here
