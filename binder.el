;;; binder.el --- major mode for structuring multi-file projects  -*- lexical-binding: t; -*-

;; Copyright (c) 2019 Paul W. Rankin

;; Author: Paul W. Rankin <hello@paulwrankin.com>
;; Keywords: files, outlines

;; This program is free software; you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free Software
;; Foundation, either version 3 of the License, or (at your option) any later
;; version.

;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
;; details.

;; You should have received a copy of the GNU General Public License along with
;; this program. If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; 


;;; Code:

(defgroup binder ()
  "Work with a structured project of files."
  :group 'files)


;;; Options

(defcustom binder-mode-lighter " B/"
  "Mode-line indicator for `binder-mode'."
  :type '(choice (const :tag "No lighter" "") string)
  :safe 'stringp)

(defcustom binder-default-file ".binder.el"
  "Default file in which to store Binder project data."
  :type 'string
  :safe 'stringp)

(defcustom binder-file-separator "\n\n"
  "String to insert between files when joining."
  :type 'string)

(defcustom binder-pop-up-windows nil
  "Non-nil means displaying a new buffer should make a new window."
  :type 'boolean)


;;; Faces

(defface binder-sidebar-mark
  '((t (:inherit (warning))))
  "Default face marked items.")

(defface binder-sidebar-highlight
  '((t (:inherit (secondary-selection))))
  "Default face for highlighted items.")

(defface binder-sidebar-missing
  '((t (:inherit (trailing-whitespace))))
  "Default face for missing items.")

(defface binder-sidebar-remove
  '((t (:inherit (error))))
  "Default face for items marked for removal.")


;;; Core Variabels

(defvar binder-alist
  nil
  "Global binder alist data.")


;;; Core Functions

(defun binder-find-binder-file (&optional dir)
  (let ((binder-file
         (expand-file-name
          binder-default-file
          (locate-dominating-file (or dir default-directory)
                                  binder-default-file))))
    (if (file-readable-p binder-file) binder-file)))

(defun binder-read ()
  (or dir (setq dir default-directory))
  (let ((binder-file (or (binder-find-binder-file)
                         (user-error "No binder file found"))))
    (unless (and (string= dir (get 'binder-alist 'dir))
                 (time-less-p (file-attribute-modification-time
                               (file-attributes binder-file))
                              (get 'binder-alist 'modtime)))
      (with-temp-buffer
        (insert-file-contents binder-file)
        (setq binder-alist (read (current-buffer)))))
    (put 'binder-alist 'dir dir)
    (put 'binder-alist 'modtime (current-time)))
  binder-alist)

(defun binder-write ()
  (interactive)
  (let ((binder-file
         (or (binder-find-binder-file)
             (if (y-or-n-p (format "Create `%s' in %s? "
                                   binder-default-file default-directory))
                 (expand-file-name binder-default-file)))))
    (with-temp-buffer
      (insert "\
;; -*- coding: utf-8; -*-
;; This is a Binder project file. It is meant to be human-readable, but you
;; probably shouldn't edit it.\n\n"
              (pp (binder-read)))
      (write-file binder-file))))

(defun binder-get-structure ()
  (alist-get 'structure (binder-read)))

(defun binder-get-item (id)
  (assoc-string id (binder-get-structure)))

(defun binder-get-item-prop (id prop)
  (alist-get prop (cdr (binder-get-item id))))


;;; Global Minor Mode

(defun binder-next-file (&optional n)
  "Goto Nth next file in `binder-alist'.
Or goto Nth previous file if N is negative."
  (interactive "p")
  ;; FIXME: error on dired buffers
  (let* ((this-file (file-name-nondirectory (buffer-file-name)))
         (structure (binder-get-structure))
         item index next-index next-file)
    (setq item (binder-get-item this-file))
    (if (not item)
        (user-error "Item `%s' not in a binder" this-file)
      (setq index (seq-position structure item 'eq)
            next-index (+ index n))
      (if (and (<= 0 next-index)
               (< next-index (length structure)))
          (and
           (setq next-file (expand-file-name (car (nth next-index structure))
                                             default-directory))
           (find-file-existing next-file))
        (message "End of binder"))
      (set-transient-map
       (let ((map (make-sparse-keymap)))
         (define-key map "]" #'binder-next-file)
         (define-key map "[" #'binder-previous-file) map)))))

(defun binder-previous-file (&optional n)
  "Goto Nth previous file in `binder-alist'.
Or goto Nth next file if N is negative."
  (interactive "p")
  (binder-next-file (- n)))

(defvar binder-mode-map (make-sparse-keymap))

(define-key binder-mode-map (kbd "C-c ]") #'binder-next-file)
(define-key binder-mode-map (kbd "C-c [") #'binder-previous-file)
(define-key binder-mode-map (kbd "C-c ;") #'binder-toggle-sidebar)

;;;###autoload
(define-minor-mode binder-mode
  "Globally interact with `binder'."
  :init-value nil
  :lighter binder-mode-lighter
  :keymap binder-mode-map
  :global t)


;;; Sidebar Major Mode

(defcustom binder-sidebar-display-alist
  '((side . left)
    (window-width . 35)
    (slot . -1))
  "Alist used to display binder sidebar buffer.

See `display-buffer-in-side-window' for example options."
  :type 'alist)

(defcustom binder-sidebar-select-window
  t
  "If non-nil, switch to binder sidebar upon displaying it."
  :type 'boolean)

(defun binder-sidebar-list ()
  (let ((buffer (get-buffer-create "*Binder Sidebar*"))
        (structure (binder-get-structure)))
        (with-current-buffer buffer
          (with-silent-modifications
            (let ((x (point)))
              (erase-buffer)
              (dolist (item structure)
                (let ((id (car item))
                      (filename (alist-get 'filename item))
                      (notes (alist-get 'notes item))
                      (tags (alist-get 'tags item)))
                  (insert " "
                          (cond ((and filename (not (file-exists-p filename)))
                                 "?")
                                ((and notes (not (string-empty-p notes)))
                                 "*")
                                (t " "))
                          " " id)
                  (put-text-property (line-beginning-position)
                                     (line-end-position)
                                     'binder-id id)
                  (put-text-property (line-beginning-position)
                                     (line-end-position)
                                     'front-sticky '(binder-id))
                  (insert "\n")))
              (goto-char x))
            (binder-sidebar-mode))
          (current-buffer))))

(defun binder-sidebar-refresh ()
  (interactive)
  (binder-sidebar-list))

(defun binder-sidebar-get-id ()
  (save-excursion
    (beginning-of-line)
    (get-text-property (point) 'binder-id)))

(defun binder-sidebar-find-file ()
  (interactive)
  (let ((pop-up-windows binder-pop-up-windows))
    (find-file-existing
     (alist-get 'filename (binder-get-item
                           (or (binder-sidebar-get-id)
                               (user-error "No item at point")))))))

(defun binder-sidebar-mark ()
  (interactive)
  (beginning-of-line)
  ;; (bookmark-bmenu-ensure-position)
  (let ((inhibit-read-only t))
    (delete-char 1)
    (insert-and-inherit ">")
    (put-text-property (line-beginning-position)
                       (line-end-position)
                       'face 'binder-sidebar-mark)
    (forward-line 1)))

(defun binder-sidebar-unmark ()
  (interactive)
  (beginning-of-line)
  (let ((inhibit-read-only t))
    (delete-char 1)
    (insert-and-inherit " ")
    (put-text-property (line-beginning-position)
                       (line-end-position)
                       'face nil)
    (forward-line 1)))

(defun binder-sidebar-get-index ()
  (let (item)
    (setq item (binder-get-item (binder-sidebar-get-id)))
    (seq-position (binder-get-structure) item 'eq)))
)

(defun binder-sidebar-shift-down (&optional n)
  (interactive "p")
  (let ((p (if (<= n 0) -1 1))
        (structure (binder-get-structure))
        (index (binder-sidebar-get-index))
        tail)
    (setq tail (copy-sequence (nthcdr index structure)))
    (setcar (nthcdr index structure)
            (nth (+ index p) structure))
    (setcar (nthcdr (+ index p) structure)
            (car tail))
    (binder-sidebar-list)
    ;; This won't work forever...
    (forward-line p)))

(defun binder-sidebar-shift-up (&optional n)
  (interactive "p")
  (binder-sidebar-shift-down (- n)))

(defun binder-sidebar-multiview ()
  (interactive)
  (let ((alist (binder-read))
        buffer mode filename-list)
    (setq buffer (get-buffer-create "*Binder Multiview*")
          mode (alist-get 'default-mode alist))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^>" nil t)
        (setq filename-list
              (cons (alist-get 'filename
                               (binder-get-item (binder-sidebar-get-id)
                                                alist))
                    filename-list))))
    (setq filename-list (reverse filename-list))
    (with-current-buffer buffer
      (with-silent-modifications
        (erase-buffer)
        (dolist (file filename-list)
          (insert-file-contents file)
          (goto-char (point-max))
          (insert binder-file-separator)))
      (if mode (funcall mode))
      (view-mode t))
    (pop-to-buffer buffer)))

(defun binder-toggle-sidebar ()
  (interactive)
  (let ((display-buffer-mark-dedicated t)
        (dir default-directory)
        (buffer (binder-sidebar-list)))
    (if (get-buffer-window buffer (selected-frame))
        (delete-windows-on buffer (selected-frame))
      (display-buffer-in-side-window buffer binder-sidebar-display-alist)
      (with-current-buffer buffer
        (setq default-directory dir))
      (if binder-sidebar-select-window
          (select-window (get-buffer-window buffer (selected-frame)))))))

;;;###autoload
(define-derived-mode binder-sidebar-mode
  special-mode "Binder Sidebar"
  "Major mode for working with `binder' projects."
  (cursor-sensor-mode t))

(define-key binder-sidebar-mode-map (kbd "g") #'binder-sidebar-refresh)
(define-key binder-sidebar-mode-map (kbd "n") #'next-line)
(define-key binder-sidebar-mode-map (kbd "p") #'previous-line)
(define-key binder-sidebar-mode-map (kbd "RET") #'binder-sidebar-find-file)
(define-key binder-sidebar-mode-map (kbd "s") #'binder-write)
(define-key binder-sidebar-mode-map (kbd "m") #'binder-sidebar-mark)
(define-key binder-sidebar-mode-map (kbd "u") #'binder-sidebar-unmark)
(define-key binder-sidebar-mode-map (kbd "v") #'binder-sidebar-multiview)
(define-key binder-sidebar-mode-map (kbd "i") #'binder-sidebar-toggle-notes)
(define-key binder-sidebar-mode-map (kbd "a") #'binder-sidebar-open-notes)
(define-key binder-sidebar-mode-map (kbd "M-n") #'binder-sidebar-shift-down)
(define-key binder-sidebar-mode-map (kbd "M-p") #'binder-sidebar-shift-up)
;; (define-key binder-sidebar-mode-map (kbd "a") #'binder-sidebar-add)
;; (define-key binder-sidebar-mode-map (kbd "U") #'binder-sidebar-unmark-all)
;; (define-key binder-sidebar-mode-map (kbd "d") #'binder-sidebar-remove)
;; (define-key binder-sidebar-mode-map (kbd "r") #'binder-sidebar-rename)


;;; Notes Major Mode

(defcustom binder-notes-display-alist
  '((side . left)
    (slot . 1))
  "Alist used to display binder notes buffer.

See `display-buffer-in-side-window' for example options."
  :type 'alist)

(defvar-local binder-notes-id nil)

(defun binder-sidebar-get-notes (dir id)
  (binder-notes-mode)
  (if dir (setq default-directory dir))
  (when id
    (unless (string= binder-notes-id id)
      (setq binder-notes-id id)
      (let ((notes (alist-get 'notes (binder-get-item binder-notes-id))))
        (with-silent-modifications
          (erase-buffer)
          (if notes (insert notes)))))))

(defun binder-sidebar-toggle-notes ()
  (interactive)
  (let ((display-buffer-mark-dedicated t)
        (dir default-directory)
        (id (binder-sidebar-get-id))
        (buffer (get-buffer-create "*Binder Notes*")))
    (with-current-buffer buffer
      (binder-sidebar-get-notes dir id))
    (if (get-buffer-window buffer (selected-frame))
        (delete-windows-on buffer (selected-frame))
      (display-buffer-in-side-window buffer binder-notes-display-alist))))

(defun binder-sidebar-open-notes ()
  (interactive)
  (let ((display-buffer-mark-dedicated t)
        (dir default-directory)
        (id (binder-sidebar-get-id))
        (buffer (get-buffer-create "*Binder Notes*")))
    (with-current-buffer buffer
      (binder-sidebar-get-notes dir id)
    (display-buffer-in-side-window buffer binder-notes-display-alist)
    (select-window (get-buffer-window buffer (selected-frame))))))

(defun binder-notes-commit ()
  (interactive)
  (unless (derived-mode-p 'binder-notes-mode)
    (user-error "Not in binder-notes-mode"))
  (if (not (buffer-modified-p))
      (message "(No changes need to be added to binder)")
    (let ((notes-prop (assq 'notes (binder-get-item binder-notes-id)))
          (notes (buffer-substring-no-properties (point-min) (point-max))))
      (if notes-prop
          (setcdr notes-prop notes)
        (push (cons 'notes notes) (cdr (binder-get-item binder-notes-id)))))
    (set-buffer-modified-p nil)
    (message "Added notes for `%s' to binder" binder-notes-id)))

;;;###autoload
(define-derived-mode binder-notes-mode
  text-mode "Binder Notes Mode"
  "Major mode for editing `binder' notes.")

(define-key binder-notes-mode-map (kbd "C-c C-c") #'binder-notes-commit)
(define-key binder-notes-mode-map (kbd "C-c C-q") #'quit-window)

(defcustom binder-notes-mode-hook
  '(turn-on-visual-line-mode)
  "Hook run after entering Binder Notes Mode mode."
  :type 'hook
  :options '(turn-on-visual-line-mode))

(provide 'binder)
;;; binder.el ends here
