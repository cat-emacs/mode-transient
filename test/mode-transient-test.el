;;; mode-transient-test.el --- Tests for mode-transient -*- lexical-binding: t; no-byte-compile: t; -*-

(require 'ert)
(require 'mode-transient-use-package)

(defun mode-transient-test-command ()
  "Do nothing for mode-transient tests."
  (interactive))

(define-derived-mode mode-transient-test-parent-mode fundamental-mode
  "Mode-Transient Parent")

(define-derived-mode mode-transient-test-child-mode
  mode-transient-test-parent-mode "Mode-Transient Child")

(defvar mode-transient-test-minor-mode-map (make-sparse-keymap))

(define-minor-mode mode-transient-test-minor-mode
  "Minor mode used by mode-transient tests."
  :keymap mode-transient-test-minor-mode-map)

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
          (should (equal (buffer-substring-no-properties
                          (point-min) (+ (point-min) 10))
                         "Icon title"))
          (should (equal (plist-get (get-text-property (point) 'face)
                                    :family)
                         "Test Nerd Font"))
          (should-not (string-match-p "(BUG: no description)"
                                      (buffer-string)))))
    (transient-quit-all)))

(ert-deftest mode-transient-registers-use-package-keywords-once ()
  (dolist (keyword '(:transient :mode-transient :minor-mode-transient))
    (should (= 1 (cl-count keyword use-package-keywords)))))

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

(ert-deftest mode-transient-major-mode-falls-back-to-parent ()
  (mode-transient--register-mode
   'major 'mode-transient-test-parent-mode 'parent-test nil
   '(["Parent" ("p" "Parent" mode-transient-test-command)]) 'emacs)
  (with-temp-buffer
    (mode-transient-test-child-mode)
    (should
     (eq (mode-transient--major-prefix)
         'mode-transient/major/mode-transient-test-parent-mode))))

(ert-deftest mode-transient-minor-mode-installs-configured-key ()
  (mode-transient--register-mode
   'minor 'mode-transient-test-minor-mode 'minor-test
   '(:key "C-c t")
   '(["Minor" ("m" "Minor" mode-transient-test-command)]) 'emacs)
  (should
   (eq (lookup-key mode-transient-test-minor-mode-map (kbd "C-c t"))
       'mode-transient/minor/mode-transient-test-minor-mode)))

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
