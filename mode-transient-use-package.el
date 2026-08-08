;;; mode-transient-use-package.el --- use-package integration for mode-transient -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Misaka

;; Author: Misaka <chuxubank@qq.com>

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; This library installs the `:transient', `:mode-transient', and
;; `:minor-mode-transient' use-package keywords for `mode-transient'.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'mode-transient)
(require 'use-package-core)

(defconst mode-transient--use-package-error
  "Mode-transient keywords expect a target, optional option plist, and native Transient groups")

(defun mode-transient--normalize-clause (target-kind args)
  "Normalize `use-package' ARGS for TARGET-KIND."
  (unless (and (listp args) args)
    (use-package-error mode-transient--use-package-error))
  (let ((target (pop args)) options)
    (unless (if (eq target-kind 'prefix)
                (and target (symbolp target))
              (or (and target (symbolp target))
                  (and (consp target) (seq-every-p #'symbolp target))))
      (use-package-error mode-transient--use-package-error))
    (when (and (listp (car args)) (keywordp (caar args)))
      (setq options (pop args)))
    (unless args
      (use-package-error mode-transient--use-package-error))
    (list target options args)))

(defun mode-transient--use-package-normalize-prefix
    (_package _keyword arglists)
  "Normalize `use-package' :transient ARGLISTS."
  (mapcar (lambda (args)
            (mode-transient--normalize-clause 'prefix args))
          arglists))

(defun mode-transient--use-package-normalize-mode
    (_package _keyword arglists)
  "Normalize mode-transient `use-package' ARGLISTS."
  (mapcar (lambda (args)
            (mode-transient--normalize-clause 'mode args))
          arglists))

(defun mode-transient--use-package-handler-prefix
    (package keyword args rest state)
  "Handle `use-package' KEYWORD ARGS for PACKAGE with REST and STATE."
  (use-package-concat
   (use-package-process-keywords package rest state)
   (cl-loop for (prefix options groups) in args
            for index from 0
            collect
            `(mode-transient--set-contribution
              ',prefix '(,package ,keyword ,index) ',options ',groups))))

(defun mode-transient--use-package-handler-mode
    (kind package keyword args rest state)
  "Handle KIND mode-transient KEYWORD ARGS for PACKAGE."
  (use-package-concat
   (use-package-process-keywords package rest state)
   (cl-loop for (modes options groups) in args
            for index from 0
            collect
            `(mode-transient--register-mode
              ',kind ',modes '(,package ,keyword ,index)
              ',options ',groups ',package))))

(defun mode-transient--use-package-handler-major
    (package keyword args rest state)
  "Handle major-mode KEYWORD ARGS for PACKAGE with REST and STATE."
  (mode-transient--use-package-handler-mode
   'major package keyword args rest state))

(defun mode-transient--use-package-handler-minor
    (package keyword args rest state)
  "Handle minor-mode KEYWORD ARGS for PACKAGE with REST and STATE."
  (mode-transient--use-package-handler-mode
   'minor package keyword args rest state))

(defun mode-transient--unwrap-command (command)
  "Return the symbol named by a function-quoted COMMAND."
  (if (and (eq (car-safe command) 'function)
           (symbolp (cadr command)))
      (cadr command)
    command))

(defun mode-transient--suffix-command (suffix)
  "Return the command symbol from native Transient SUFFIX."
  (let ((items suffix))
    (when (integerp (car items))
      (pop items))
    (if (keywordp (car items))
        (mode-transient--unwrap-command (plist-get items :command))
      (when (or (stringp (car items))
                (vectorp (car items)))
        (pop items))
      (when (or
             (stringp (car items))
             (and (eq (car-safe (car items)) 'lambda)
                  (not (commandp (car items))))
             ;; A non-string dynamic description is followed by the command.
             (and (cdr items)
                  (not (keywordp (cadr items)))))
        (pop items))
      (mode-transient--unwrap-command (car items)))))

(defun mode-transient--group-commands (group)
  "Return command autoloads found in native Transient GROUP."
  (when (vectorp group)
    (pcase-let ((`(,_ ,children) (mode-transient--group-parts group)))
      (cl-mapcan
       (lambda (child)
         (cond
          ((vectorp child) (mode-transient--group-commands child))
          ((listp child)
           (let ((command (mode-transient--suffix-command child)))
             (and (symbolp command) (list (cons command 'command)))))))
       children))))

(defun mode-transient--use-package-autoloads
    (_package _keyword args)
  "Return command autoloads from normalized mode-transient ARGS."
  (delete-dups
   (cl-mapcan
    (lambda (entry)
      (cl-mapcan #'mode-transient--group-commands (nth 2 entry)))
    args)))

(defun mode-transient--add-use-package-keyword (keyword)
  "Add KEYWORD beside binding keywords in `use-package-keywords'."
  (setq use-package-keywords
        (cl-loop for item in use-package-keywords
                 if (eq item :bind-keymap*)
                 collect item and collect keyword
                 else unless (eq item keyword)
                 collect item)))

(defun mode-transient--enable-use-package ()
  "Enable mode-transient use-package integration."
  (with-eval-after-load 'use-package-core
    (dolist (keyword '(:transient :mode-transient :minor-mode-transient))
      (mode-transient--add-use-package-keyword keyword))
    (defalias 'use-package-normalize/:transient
      #'mode-transient--use-package-normalize-prefix)
    (defalias 'use-package-handler/:transient
      #'mode-transient--use-package-handler-prefix)
    (defalias 'use-package-autoloads/:transient
      #'mode-transient--use-package-autoloads)
    (dolist (keyword '(:mode-transient :minor-mode-transient))
      (defalias (intern (format "use-package-normalize/%s" keyword))
        #'mode-transient--use-package-normalize-mode)
      (defalias (intern (format "use-package-autoloads/%s" keyword))
        #'mode-transient--use-package-autoloads))
    (defalias 'use-package-handler/:mode-transient
      #'mode-transient--use-package-handler-major)
    (defalias 'use-package-handler/:minor-mode-transient
      #'mode-transient--use-package-handler-minor)))


(mode-transient--enable-use-package)

(provide 'mode-transient-use-package)

;;; mode-transient-use-package.el ends here
