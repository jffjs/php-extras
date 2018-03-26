;;; php-extras-gen-eldoc.el --- Extra features for `php-mode'

;; Copyright (C) 2012, 2013, 2014 Arne Jørgensen

;; Author: Arne Jørgensen <arne@arnested.dk>

;; This software is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This software is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this software.  If not, see
;; <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Download and parse PHP manual from php.net and build a new
;; `php-extras-function-arguments' hash table of PHP functions and
;; their arguments.

;; Please note that build a new `php-extras-function-arguments' is a
;; slow process and might be error prone.

;;; Code:

(require 'php-mode)
(require 'php-extras)
(require 'json)
(require 'shr)


(defvar php-extras-php-doc-url
  "http://doc.php.net/downloads/json/php_manual_en.json"
  "URL of the JSON list of PHP functions.")


;;;###autoload
(defun php-extras-generate-eldoc ()
  "Regenerate PHP function argument hash table from php.net. This is slow!"
  (interactive)
  (when (yes-or-no-p "Regenerate PHP function argument hash table from php.net? This is slow! ")
    (php-extras-generate-eldoc-1 t)))

(defun php-extras-generate-eldoc-1 (&optional byte-compile)
  (with-current-buffer (url-retrieve-synchronously php-extras-php-doc-url)
    (search-forward-regexp "^$")
    (let* ((data (json-read))
           (count 0)
           (progress 0)
           (length (length data))
           (function-arguments-temp (make-hash-table
                                     :size length
                                     :rehash-threshold 1.0
                                     :rehash-size 100
                                     :test 'equal))
           doc)
      (dolist (elem data)
        (setq count (+ count 1))
        ;; Skip methods for now: is there anything more intelligent we
        ;; could do with them?
        (unless (string-match-p "::" (symbol-name (car elem)))
          (setq progress (* 100 (/ (float count) length)))
          (message "[%2d%%] Adding function: %s..." progress (car elem))
          (setq doc (concat
                     (cdr (assoc 'purpose (cdr elem)))
                     "\n\n"
                     (cdr (assoc 'prototype (cdr elem)))
                     "\n\n"
                     ;; The return element is HTML - use `shr' to
                     ;; render it back to plain text.
                     (save-window-excursion
                       (with-temp-buffer
                         (insert (cdr (assoc 'return (cdr elem))))
                         (shr-render-buffer (current-buffer))
                         (delete-trailing-whitespace)
                         (buffer-string)))
                     "\n\n"
                     "(" (cdr (assoc 'versions (cdr elem))) ")"))
          (puthash (symbol-name (car elem)) (cons `(documentation . ,doc) (cdr elem)) function-arguments-temp)))
      ;; PHP control structures are not present in JSON list. We add
      ;; them here (hard coded - there are not so many of them).
      (let ((php-control-structures '("if" "else" "elseif" "while" "do.while" "for" "foreach" "break" "continue" "switch" "declare" "return" "require" "include" "require_once" "include_once" "goto")))
        (dolist (php-control-structure php-control-structures)
          (message "Adding control structure: %s..." php-control-structure)
          (puthash php-control-structure
                   '((purpose . "Control structure")
                     (id . (concat "control-structures." php-control-structure)))
                   function-arguments-temp)))
      (let* ((file (concat php-extras-eldoc-functions-file ".el"))
             (base-name (file-name-nondirectory php-extras-eldoc-functions-file)))
        (with-temp-file file
          (insert (format
                   ";;; %s.el -- file auto generated by `php-extras-generate-eldoc'

\(require 'php-extras)

\(setq php-extras-function-arguments %S)

\(provide 'php-extras-eldoc-functions)

;;; %s.el ends here
"
                   base-name
                   function-arguments-temp
                   base-name)))
        (when byte-compile
          (message "Byte compiling and loading %s ..." file)
          (byte-compile-file file t)
          (message "Byte compiling and loading %s ... done." file))))))

(provide 'php-extras-gen-eldoc)

;;; php-extras-gen-eldoc.el ends here
