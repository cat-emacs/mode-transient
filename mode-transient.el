;;; mode-transient.el --- Composable Transient menus for modes -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Misaka

;; Author: Misaka <chuxubank@qq.com>
;; Maintainer: Misaka <chuxubank@qq.com>
;; Version: 0.2.0
;; Package-Requires: ((emacs "29.1") (transient "0.13.0"))
;; Keywords: convenience, transient
;; URL: https://github.com/cat-emacs/mode-transient

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `mode-transient' provides composable Transient menus and use-package
;; integration.  Group and suffix specifications use Transient's native
;; syntax, so levels, predicates, infixes, dynamic descriptions, and nested
;; prefixes work without an adapter language.
;; Prefix `:description' values are rendered as an always-visible outer group
;; title.  Forms are automatically wrapped in a zero-argument function.
;; Suffixes without descriptions fall back to their command summary or name.
;;
;; Define a menu that other packages can extend:
;;
;;   (mode-transient-define-prefix my-tools ()
;;     :description "Tools")
;;
;;   (use-package foo
;;     :transient
;;     (my-tools
;;      ["Foo"
;;       ("f" "Run foo" foo-run)]))
;;
;; Add commands to a major-mode menu:
;;
;;   (use-package foo
;;     :major-transient
;;     (prog-mode
;;      ["Foo"
;;       ("f" "Run foo" foo-run)]))
;;
;; Minor-mode menus can also install a key in the minor-mode map.  The map is
;; inferred from the mode name unless `:keymap' is specified:
;;
;;   (use-package foo
;;     :minor-transient
;;     (foo-mode
;;      (:key "C-c f")
;;      ["Foo"
;;       ("r" "Refresh" foo-refresh)]))

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'transient)

(defgroup mode-transient nil
  "Composable Transient menus for major and minor modes."
  :group 'convenience
  :prefix "mode-transient-")

(defun mode-transient-default-title (mode kind)
  "Return a default title for MODE of KIND."
  (ignore kind)
  (format "%s Commands"
          (capitalize
           (replace-regexp-in-string
            "-" " "
            (replace-regexp-in-string
             "\\(?:-major\\|-minor\\)?-mode\\'" "" (symbol-name mode))))))

(defcustom mode-transient-title-function #'mode-transient-default-title
  "Function used to title generated mode Transients.
The function receives the mode symbol and either `major' or `minor'."
  :type 'function
  :group 'mode-transient)

(defcustom mode-transient-hide-cursor t
  "Whether to hide the cursor in menus built by mode-transient."
  :type 'boolean
  :group 'mode-transient)

(defun mode-transient-command-name (suffix)
  "Return the command name represented by Transient SUFFIX."
  (symbol-name (oref suffix command)))

(defvar mode-transient--major-prefixes nil
  "Alist mapping major modes to their generated Transient prefixes.")

(defvar mode-transient--minor-prefixes nil
  "Alist mapping minor modes to their generated Transient prefixes.")

(defconst mode-transient--base-property 'mode-transient--base)
(defconst mode-transient--contributions-property
  'mode-transient--contributions)

(defun mode-transient--hide-menu-cursor ()
  "Hide the cursor in the active mode-transient menu."
  (when (and mode-transient-hide-cursor
             (buffer-live-p transient--buffer))
    (with-current-buffer transient--buffer
      (setq-local cursor-type nil)
      (setq-local cursor-in-non-selected-windows nil))))

(defun mode-transient--normalize-description (description)
  "Return a native dynamic Transient DESCRIPTION.
Wrap non-literal forms in a zero-argument function."
  (if (or (stringp description)
          (symbolp description)
          (memq (car-safe description) '(function lambda)))
      description
    `(lambda () ,description)))

(defun mode-transient--normalize-options (options)
  "Normalize convenience values in prefix OPTIONS."
  (let (result)
    (while options
      (let ((key (pop options))
            (value (pop options)))
        (setq result
              (append result
                      (list key
                            (if (eq key :description)
                                (mode-transient--normalize-description value)
                              value))))))
    result))

(defun mode-transient--split-prefix-args (args)
  "Split transient prefix ARGS into docstring, options, and groups."
  (let (docstring options)
    (when (stringp (car args))
      (setq docstring (pop args)))
    (while (keywordp (car args))
      (unless (cdr args)
        (error "Missing value for mode-transient prefix option %S"
               (car args)))
      (setq options (append options (list (pop args) (pop args)))))
    (list docstring (mode-transient--normalize-options options) args)))

(defun mode-transient--merge-options (base extra)
  "Return prefix options from BASE overlaid by EXTRA."
  (let ((result (copy-sequence base)))
    (while extra
      (setq result (plist-put result (pop extra) (pop extra))))
    result))

(defun mode-transient--without-options (options omitted)
  "Return OPTIONS without keys listed in OMITTED."
  (let (result)
    (while options
      (let ((key (pop options))
            (value (pop options)))
        (unless (memq key omitted)
          (setq result (append result (list key value))))))
    result))

(defun mode-transient--group-parts (group)
  "Return the header and children of native Transient GROUP."
  (let ((items (append group nil)) header)
    (when (integerp (car items))
      (push (pop items) header))
    (when (stringp (car items))
      (push (pop items) header))
    (while (keywordp (car items))
      (unless (cdr items)
        (error "Missing value for Transient group option %S" (car items)))
      (push (pop items) header)
      (push (pop items) header))
    (list (vconcat (nreverse header)) items)))

(defun mode-transient--group-description (header)
  "Return the description represented by group HEADER."
  (let ((items (append header nil)) description)
    (when (integerp (car items))
      (pop items))
    (if (stringp (car items))
        (car items)
      (while items
        (let ((key (pop items))
              (value (pop items)))
          (when (eq key :description)
            (setq description value))))
      description)))

(defun mode-transient--merge-groups (groups)
  "Merge native Transient GROUPS that have identical named headers."
  (let (result)
    (dolist (group groups)
      (if (not (vectorp group))
          (setq result (append result (list group)))
        (pcase-let* ((`(,header ,children)
                       (mode-transient--group-parts group))
                      (description
                       (mode-transient--group-description header))
                      (index
                       (and description
                            (cl-position-if
                             (lambda (existing)
                               (and (vectorp existing)
                                    (pcase-let ((`(,other-header ,_)
                                                 (mode-transient--group-parts
                                                  existing)))
                                      (equal header other-header))))
                             result))))
          (if (null index)
              (setq result (append result (list group)))
            (pcase-let ((`(,existing-header ,existing-children)
                         (mode-transient--group-parts (nth index result))))
              (setf (nth index result)
                    (vconcat existing-header existing-children children)))))))
    result))

(defun mode-transient--default-docstring (prefix)
  "Return a readable default docstring for PREFIX."
  (format "%s menu"
          (capitalize
           (replace-regexp-in-string "[-/]" " " (symbol-name prefix)))))

(defun mode-transient--rebuild (prefix)
  "Rebuild PREFIX from its base and registered contributions."
  (pcase-let* ((base (or (get prefix mode-transient--base-property)
                         (list (mode-transient--default-docstring prefix)
                               nil nil)))
                (`(,docstring ,options ,groups) base))
    (dolist (entry (get prefix mode-transient--contributions-property))
      (setq options (mode-transient--merge-options
                     options (copy-sequence (nth 1 entry)))
            groups (append groups (copy-tree (nth 2 entry)))))
    (let ((description (plist-get options :description)))
      (unless (plist-member options :suffix-description)
        (setq options
              (append options
                      '(:suffix-description
                        #'mode-transient-command-name))))
      (setq options (mode-transient--without-options options '(:description))
            groups (mode-transient--merge-groups groups))
      (when description
        (setq groups
              (list (vconcat (list :description description) groups)))))
    (eval `(transient-define-prefix ,prefix ()
             ,@(and docstring (list docstring))
             ,@options
             ,@(or groups (list []))
             (interactive)
             (transient-setup ',prefix)
             (mode-transient--hide-menu-cursor))
          t)))

(defun mode-transient--set-base (prefix args)
  "Set PREFIX base definition from native Transient ARGS."
  (put prefix mode-transient--base-property
       (mode-transient--split-prefix-args args))
  (mode-transient--rebuild prefix))

;;;###autoload
(defmacro mode-transient-define-prefix (name arglist &rest args)
  "Define composable Transient prefix NAME using native Transient ARGS.
ARGLIST must be empty.  Unlike `transient-define-prefix', the definition may
initially contain no groups because `use-package' declarations can add them
later."
  (declare (indent 2))
  (unless (null arglist)
    (error "Mode-transient prefixes do not support arguments"))
  `(mode-transient--set-base ',name ',args))

(defun mode-transient--set-contribution
    (prefix source options groups)
  "Set SOURCE contribution of OPTIONS and GROUPS on PREFIX."
  (let* ((options (mode-transient--normalize-options options))
         (entries (get prefix mode-transient--contributions-property))
         (entry (assoc source entries)))
    (if entry
        (setcdr entry (list options groups))
      (setq entries
            (append entries (list (list source options groups)))))
    (put prefix mode-transient--contributions-property entries)
    (mode-transient--rebuild prefix)))

(defun mode-transient--mode-prefix (mode kind)
  "Return the generated Transient prefix for MODE of KIND."
  (intern (format "mode-transient/%s/%s" kind mode)))

(defun mode-transient--mode-base (mode kind)
  "Return a base definition for MODE of KIND."
  (list (format "%s commands" mode)
        `(:description
          (lambda ()
            (funcall mode-transient-title-function
                     ,(if (eq kind 'major) 'major-mode `',mode)
                     ',kind)))
        nil))

(defun mode-transient--remove-mode-options (options)
  "Remove mode-specific options from prefix OPTIONS."
  (mode-transient--without-options options '(:key :keymap :feature)))

(defun mode-transient--unquote (value)
  "Return VALUE without one `quote' wrapper."
  (if (eq (car-safe value) 'quote)
      (cadr value)
    value))

(defun mode-transient--install-binding (keymap key prefix)
  "Bind KEY to PREFIX in KEYMAP when KEYMAP is available."
  (setq keymap (mode-transient--unquote keymap))
  (cond
   ((not (and (symbolp keymap) (boundp keymap)))
    (display-warning
     'mode-transient
     (format "Cannot bind %s: keymap %S is not defined" key keymap)
     :warning))
   ((not (keymapp (symbol-value keymap)))
    (display-warning
     'mode-transient
     (format "Cannot bind %s: %S does not contain a keymap" key keymap)
     :warning))
   (t
    (define-key (symbol-value keymap)
                (cond ((stringp key) (kbd key))
                      ((vectorp key) key)
                      (t (eval key t)))
                prefix))))

(defun mode-transient--schedule-binding
    (mode prefix options default-feature)
  "Install the mode binding described by OPTIONS for MODE and PREFIX.
DEFAULT-FEATURE is used when OPTIONS does not contain `:feature'."
  (when-let ((key (and (plist-member options :key)
                       (plist-get options :key))))
    (let* ((keymap (or (plist-get options :keymap)
                       (intern (format "%s-map" mode))))
           (feature (or (mode-transient--unquote
                         (plist-get options :feature))
                        default-feature)))
      (if (and (symbolp (mode-transient--unquote keymap))
               (boundp (mode-transient--unquote keymap)))
          (mode-transient--install-binding keymap key prefix)
        (eval-after-load feature
          `(mode-transient--install-binding ',keymap ',key ',prefix))))))

(defun mode-transient--register-mode
    (kind modes source options groups feature)
  "Register a KIND menu contribution for MODES from SOURCE.
OPTIONS and GROUPS use native Transient syntax.  FEATURE controls deferred
installation of an optional mode-local key."
  (dolist (mode (if (listp modes) modes (list modes)))
    (unless (symbolp mode)
      (error "Invalid %s mode name: %S" kind mode))
    (let ((prefix (mode-transient--mode-prefix mode kind)))
      (unless (get prefix mode-transient--base-property)
        (put prefix mode-transient--base-property
             (mode-transient--mode-base mode kind)))
      (if (eq kind 'major)
          (setf (alist-get mode mode-transient--major-prefixes) prefix)
        (setf (alist-get mode mode-transient--minor-prefixes) prefix))
      (mode-transient--set-contribution
       prefix source (mode-transient--remove-mode-options options) groups)
      (mode-transient--schedule-binding mode prefix options feature))))

(defun mode-transient--major-prefix (&optional mode)
  "Return the closest registered prefix for major MODE."
  (let ((mode (or mode major-mode)) prefix)
    (while (and mode (not prefix))
      (setq prefix (alist-get mode mode-transient--major-prefixes)
            mode (get mode 'derived-mode-parent)))
    prefix))

;;;###autoload
(defun mode-transient ()
  "Show the Transient registered for the current major mode."
  (interactive)
  (if-let ((prefix (mode-transient--major-prefix)))
      (call-interactively prefix)
    (user-error "No Transient registered for %s or its parent modes"
                major-mode)))

(defun mode-transient--active-minor-prefixes ()
  "Return registered, active minor modes and their prefixes."
  (seq-filter
   (lambda (entry)
     (and (boundp (car entry))
          (symbol-value (car entry))
          (fboundp (cdr entry))))
   mode-transient--minor-prefixes))

;;;###autoload
(defun mode-transient-minor ()
  "Show a Transient for an active registered minor mode.
Prompt when more than one active minor mode has a registered menu."
  (interactive)
  (let ((active (mode-transient--active-minor-prefixes)))
    (pcase (length active)
      (0 (user-error "No active minor mode has a registered Transient"))
      (1 (call-interactively (cdar active)))
      (_
       (let* ((choices
               (mapcar
                (lambda (entry)
                  (cons (funcall mode-transient-title-function
                                 (car entry) 'minor)
                        (cdr entry)))
                active))
              (prefix
               (cdr (assoc (completing-read "Minor mode Transient: "
                                            choices nil t)
                           choices))))
         (call-interactively prefix))))))

(provide 'mode-transient)

;;; mode-transient.el ends here
