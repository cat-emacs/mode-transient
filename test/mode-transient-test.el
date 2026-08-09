;;; mode-transient-test.el --- Tests for mode-transient -*- lexical-binding: t; no-byte-compile: t; -*-

(require 'ert)
(require 'mode-transient-use-package)

(defun mode-transient-test-command ()
  "Do nothing for mode-transient tests."
  (interactive))

(define-derived-mode mode-transient-test-grandparent-mode fundamental-mode
  "Mode-Transient Grandparent")

(define-derived-mode mode-transient-test-parent-mode
  mode-transient-test-grandparent-mode
  "Mode-Transient Parent")

(define-derived-mode mode-transient-test-child-mode
  mode-transient-test-parent-mode "Mode-Transient Child")

(defvar mode-transient-test-minor-mode-map (make-sparse-keymap))

(define-minor-mode mode-transient-test-minor-mode
  "Minor mode used by mode-transient tests."
  :keymap mode-transient-test-minor-mode-map)

(define-derived-mode mode-transient-test-keyword-major-mode fundamental-mode
  "Mode-Transient Keyword Major")

(define-minor-mode mode-transient-test-keyword-minor-mode
  "Minor mode registered through the use-package adapter.")

(ert-deftest mode-transient-wraps-description-forms ()
  (mode-transient-define-prefix mode-transient-test-description ()
    :description (format "Buffer: %s" (buffer-name))
    ["Test"
     ("t" "Test" mode-transient-test-command)])
  (let* ((base (get 'mode-transient-test-description
                    'mode-transient--base))
         (description (plist-get (nth 1 base) :description)))
    (should (eq (car description) 'lambda))
    (should (string-prefix-p "Buffer: "
                             (funcall (eval description t))))))

(ert-deftest mode-transient-renders-dynamic-title-with-text-properties ()
  (mode-transient-define-prefix mode-transient-test-rendered-title ()
    :description (propertize "Icon title"
                            'face '(:family "Test Nerd Font"))
    ["Test"
     ("t" mode-transient-test-command)])
  (unwind-protect
      (progn
        (mode-transient-test-rendered-title)
        (with-current-buffer transient--buffer-name
          (goto-char (point-min))
          (should-not cursor-type)
          (should-not cursor-in-non-selected-windows)
          (should (equal (buffer-substring-no-properties
                          (point-min) (+ (point-min) 10))
                         "Icon title"))
          (should (equal (plist-get (get-text-property (point) 'face)
                                    :family)
                         "Test Nerd Font"))
          (should-not (string-match-p "(BUG: no description)"
                                      (buffer-string)))))
    (transient-quit-all)))

(ert-deftest mode-transient-leaves-other-transient-cursors-alone ()
  (transient-define-prefix mode-transient-test-native-prefix ()
    ["Native"
     ("t" "Test" mode-transient-test-command)])
  (unwind-protect
      (progn
        (mode-transient-test-native-prefix)
        (with-current-buffer transient--buffer-name
          (should (eq cursor-in-non-selected-windows 'box))))
    (transient-quit-all)))

(ert-deftest mode-transient-registers-use-package-keywords-once ()
  (should-not (fboundp 'mode-transient))
  (should (fboundp 'mode-transient-major))
  (dolist (keyword '(:transient :major-transient :minor-transient))
    (should (= 1 (cl-count keyword use-package-keywords))))
  (dolist (keyword '(:mode-transient :minor-mode-transient))
    (should-not (memq keyword use-package-keywords))))

(ert-deftest mode-transient-use-package-composes-named-groups ()
  (mode-transient-define-prefix mode-transient-test-tools ()
    :description "Test tools")
  (eval
   '(use-package emacs
      :ensure nil
      :transient
      (mode-transient-test-tools
       (:description (format "Tools: %s" (buffer-name)))
       ["One"
        ("a" "First" mode-transient-test-command)])
      (mode-transient-test-tools
       ["One"
        ("b" "Second" mode-transient-test-command)])))
  (should (fboundp 'mode-transient-test-tools))
  (let ((contributions
         (get 'mode-transient-test-tools
              'mode-transient--contributions)))
    (should (= 2 (length contributions)))
    (should
     (eq (car (plist-get (nth 1 (car contributions)) :description))
         'lambda))))

(ert-deftest mode-transient-major-inherits-all-ancestor-menus ()
  (mode-transient--register-mode
   'major 'mode-transient-test-grandparent-mode 'grandparent-test nil
   '(["Grandparent"
      ("g" "Grandparent action" mode-transient-test-command)]) 'emacs)
  (mode-transient--register-mode
   'major 'mode-transient-test-parent-mode 'parent-test nil
   '(["Parent"
      ("p" "Parent action" mode-transient-test-command)]) 'emacs)
  (mode-transient--register-mode
   'major 'mode-transient-test-child-mode 'child-test nil
   '(["Child"
      ("c" "Child action" mode-transient-test-command)]) 'emacs)
  (with-temp-buffer
    (mode-transient-test-child-mode)
    (unwind-protect
        (progn
          (mode-transient-major)
          (should
           (eq (oref transient--prefix command)
               'mode-transient/major-inherited/mode-transient-test-child-mode))
          (with-current-buffer transient--buffer-name
            (dolist (description '("Grandparent action"
                                   "Parent action"
                                   "Child action"))
              (should (string-match-p description (buffer-string))))))
      (transient-quit-all))))

(ert-deftest mode-transient-use-package-registers-major-and-minor-modes ()
  (eval
   '(use-package emacs
      :ensure nil
      :major-transient
      (mode-transient-test-keyword-major-mode
       ["Major"
        ("a" "Major" mode-transient-test-command)])
      :minor-transient
      (mode-transient-test-keyword-minor-mode
       ["Minor"
        ("i" "Minor" mode-transient-test-command)])))
  (should
   (eq (alist-get 'mode-transient-test-keyword-major-mode
                  mode-transient--major-prefixes)
       'mode-transient/major/mode-transient-test-keyword-major-mode))
  (should
   (eq (alist-get 'mode-transient-test-keyword-minor-mode
                  mode-transient--minor-prefixes)
       'mode-transient/minor/mode-transient-test-keyword-minor-mode)))

(ert-deftest mode-transient-minor-mode-installs-configured-key ()
  (mode-transient--register-mode
   'minor 'mode-transient-test-minor-mode 'minor-test
   '(:key "C-c t")
   '(["Minor" ("m" "Minor" mode-transient-test-command)]) 'emacs)
  (should
   (eq (lookup-key mode-transient-test-minor-mode-map (kbd "C-c t"))
       'mode-transient/minor/mode-transient-test-minor-mode)))

(ert-deftest mode-transient-minor-opens-the-only-active-menu ()
  (mode-transient--register-mode
   'minor 'mode-transient-test-minor-mode 'minor-dispatch-test nil
   '(["Minor" ("m" "Minor" mode-transient-test-command)]) 'emacs)
  (with-temp-buffer
    (mode-transient-test-minor-mode 1)
    (unwind-protect
        (progn
          (mode-transient-minor)
          (should
           (eq (oref transient--prefix command)
               'mode-transient/minor/mode-transient-test-minor-mode)))
      (transient-quit-all))))

(ert-deftest mode-transient-autoloads-handle-dynamic-descriptions ()
  (should
   (equal '((mode-transient-test-command . command))
          (mode-transient--use-package-autoloads
           'example :transient
           '((mode-transient-test-prefix nil
              (["Test"
                ("t" (lambda () "Dynamic")
                 mode-transient-test-command)])))))))

(provide 'mode-transient-test)

;;; mode-transient-test.el ends here
