;;; helm-org-rifle.el --- Rifle through your Org files

;; Author: Adam Porter <adam@alphapapa.net>
;; Url: http://github.com/alphapapa/org-rifle
;; Version: 2.0-pre
;; FIXME: Add Helm version to requires.
;; Package-Requires: ((emacs "24.4") (dash "2.12") (f "0.18.1") (helm "1.9.4") (s "1.10.0"))
;; Keywords: hypermedia, outlines

;;; Commentary:

;; This is my rifle.  There are many like it, but this one is mine.
;; My rifle is my best friend.  It is my life.  I must master it as I
;; must master my life.

;; What does my rifle do?  It searches rapidly through my Org files,
;; quickly bringing me the information I need to defeat the enemy.

;; This package is inspired by org-search-goto/org-search-goto-ml.  It
;; searches both headings and contents of entries in Org buffers, and
;; it displays entries that match all search terms, whether the terms
;; appear in the heading, the contents, or both.  Matching portions of
;; entries' contents are displayed with surrounding context to make it
;; easy to acquire your target.

;; Entries are fontified by default to match the appearance of an Org
;; buffer, and optionally the entire path can be displayed for each
;; entry, rather than just its own heading.

;;; Installation:

;;;; MELPA

;; If you installed from MELPA, your rifle is ready.  Just run one of
;; the commands below.

;;;; Manual

;; Install packages `dash', `f', and `s'.  Then require
;; this package in your init file:

;;   (require 'org-rifle)

;;; Usage:

;; Run one of the rifle commands, type some words, and results will be
;; displayed, grouped by buffer.  Hit "RET" to show the selected
;; entry, or <C-return> to show it in an indirect buffer.

;; FIXME: Update command list for Helm.

;; Occur commands: show results in an occur-like, persistent buffer
;; + `org-rifle': Show results from all open Org buffers
;; + `org-rifle-agenda-files': Show results from Org agenda files
;; + `org-rifle-current-buffer': Show results from current buffer
;; + `helm-org-rifle-directories': Show results from selected directories; with prefix, recursively
;; + `helm-org-rifle-files': Show results from selected files
;; + `org-rifle-org-directory': Show results from Org files in `org-directory'

;;;; Tips

;; FIXME: Update tips for org-rifle refactor.

;; + Select multiple entries in the Helm buffer to display selected
;;   entries in a read-only, `occur`-style buffer.
;; + Save all results in a Helm buffer to a `org-rifle`
;;   buffer by pressing `C-s` (like `helm-grep-save-results`).
;; + Show results from certain buffers by typing the name of the
;;   buffer (usually the filename).
;; + Show headings with certain to-do keywords by typing the keyword,
;;   e.g. `TODO` or `DONE`.
;; + Show headings with certain priorities by typing, e.g. `#A` or
;;   `[#A]`.
;; + Show headings with certain tags by searching for,
;;   e.g. `:tag1:tag2:`.
;; + Negate matches with a `!`, e.g. `pepperoni !anchovies`.
;; + Sort results by timestamp or buffer-order (the default) by
;;   calling commands with a universal prefix (`C-u`).
;; + Show entries in an indirect buffer by selecting that action from
;;   the Helm actions list, or by pressing `<C-return>`.
;; + The keymap for `org-rifle` results buffers imitates
;;   the `org-speed` keys, making it quicker to navigate. You can also
;;   collapse and expand headings and drawers with `TAB` and `S-TAB`,
;;   just like in regular Org buffers.  Results buffers are marked
;;   read-only so you cannot modify them by accidental keypresses.
;; + Delete the result at point in `org-rifle` buffers by
;;   pressing `d`.  This does not alter the source buffers but simply
;;   removes uninteresting results from view.
;; +  You can customize the `org-rifle` group if you like.

;;; Credits:

;; This package is inspired by org-search-goto (specifically,
;; org-search-goto-ml).  Its unofficial-official home is on
;; EmacsWiki[1] but I've mirrored it on GitHub[2].  It's a really
;; great package, and the only thing that could make it better is to
;; make it work with Helm.  To avoid confusion, this package has a
;; completely different name.
;;
;;  [1] https://www.emacswiki.org/emacs/org-search-goto-ml.el
;;  [2] https://github.com/alphapapa/org-search-goto

;;; License:

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

;;; Code:

;;;; Require

;; Built-in
(require 'cl-lib)
(require 'org)

;; Third-party
(require 'dash)
(require 'f)
(require 'helm)
(require 's)

(require 'org-rifle)

;;;; Vars

(defvar helm-org-rifle-map
  (let ((new-map (copy-keymap helm-map)))
    (define-key new-map (kbd "<C-return>") 'helm-org-rifle-show-entry-in-indirect-buffer-map-action)
    ;; FIXME: The C-s bind seems to only work when pressed twice;
    ;; before being pressed, it's not bound in the keymap, but after
    ;; pressing it once, it is, and then it works.  Weird.
    (define-key new-map (kbd "C-s") 'helm-org-rifle--save-results)
    (define-key new-map (kbd "C-c C-w") #'org-rifle--refile)
    new-map)
  "Keymap for `helm-org-rifle'.")

(defgroup helm-org-rifle nil
  "Settings for `helm-org-rifle'."
  :group 'helm
  :link '(url-link "https://github.com/alphapapa/org-rifle"))

(defcustom helm-org-rifle-actions
  (helm-make-actions
   "Show entry" 'helm-org-rifle--show-candidates
   "Show entry in indirect buffer" 'helm-org-rifle-show-entry-in-indirect-buffer
   "Show entry in real buffer" 'helm-org-rifle-show-entry-in-real-buffer
   "Clock in" 'helm-org-rifle--clock-in
   "Refile" 'org-rifle--refile)
  "Helm actions for `helm-org-rifle' commands."
  :type '(alist :key-type string :value-type function))

(defcustom helm-org-rifle-after-init-hook '(helm-org-rifle-set-input-idle-delay)
  "`:after-init-hook' for the Helm buffer.
If you're thinking about changing this, you probably know what you're doing."
  :group 'helm-org-rifle :type 'hook)

(defface helm-org-rifle-separator
  ;; FIXME: Pick better default color.  Black is probably too harsh.
  '((((background dark))
     :background "black")
    (((background light))
     :foreground "black"))
  "Face for `helm-org-rifle-separator', which is displayed between results.")

(defcustom helm-org-rifle-input-idle-delay 0.05
  "How long to wait to find results after the user stops typing, in seconds.
This helps prevent flickering in the Helm buffer, because the
default value for `helm-idle-input-delay' is 0.01, which runs the
search immediately after each keystroke.  You can adjust this to
get results more quickly (shorter delay) or further reduce
flickering (longer delay)."
  :type 'float)

(defcustom helm-org-rifle-multiline t
  "Show entries on multiple lines.
The heading is shown on the first line with a blank line between.
In most cases this should remain on, but it may be useful to
disable it when defining custom commands.  Note that if this is
disabled, usually `helm-org-rifle-heading-contents-separator'
should be set to a non-newline value, e.g. a space or something
like \": \"."
  :type 'boolean)

(defcustom helm-org-rifle-show-entry-function 'helm-org-rifle-show-entry-in-real-buffer
  "Default function to use to show selected entries."
  :group 'helm-org-rifle
  :type '(radio (function :tag "Show entries in real buffers." helm-org-rifle-show-entry-in-real-buffer)
                (function :tag "Show entries in indirect buffers." helm-org-rifle-show-entry-in-indirect-buffer)
                (function :tag "Custom function")))

(defcustom helm-org-rifle-show-full-contents nil
  "Show all of each result's contents instead of just context around each matching word."
  :type 'boolean)

;;;; Functions

;;;;; Commands

(cl-defmacro helm-org-rifle-defcommand (name args docstring &key sources (let nil) (transformer nil))
  "Define interactive helm-org-rifle command, which will run the appropriate hooks.
Helm will be called with vars in LET bound."
  `(cl-defun ,(intern (concat "helm-org-rifle" (when (s-present? name) (concat "-" name)))) ,args
     ,docstring
     (interactive)
     (unwind-protect
         (progn
           (run-hooks 'org-rifle-before-command-hook)
           (let* ((helm-candidate-separator " ")
                  ,(if transformer
                       ;; I wish there were a cleaner way to do this,
                       ;; because if this `if' evaluates to nil, `let' will
                       ;; try to set `nil', which causes an error.  The
                       ;; choices seem to be to a) evaluate to a list and
                       ;; unsplice it (since unsplicing `nil' evaluates to
                       ;; nothing), or b) return an ignored symbol when not
                       ;; true.  Option B is less ugly.
                       `(org-rifle-transformer ,transformer)
                     'ignore)
                  ,@let)
             (helm :sources ,sources)))
       (run-hooks 'helm-org-rifle-after-command-hook))))

;;;###autoload (autoload 'helm-org-rifle "helm-org-rifle" nil t)
(helm-org-rifle-defcommand
 "" ()
 "This is my rifle.  There are many like it, but this one is mine.

My rifle is my best friend.  It is my life.  I must master it as I
must master my life.

Without me, my rifle is useless.  Without my rifle, I am
useless.  I must fire my rifle true.  I must shoot straighter than
my enemy who is trying to kill me.  I must shoot him before he
shoots me.  I will...

My rifle and I know that what counts in war is not the rounds we
fire, the noise of our burst, nor the smoke we make.  We know that
it is the hits that count.  We will hit...

My rifle is human, even as I, because it is my life.  Thus, I will
learn it as a brother.  I will learn its weaknesses, its strength,
its parts, its accessories, its sights and its barrel.  I will
keep my rifle clean and ready, even as I am clean and ready.  We
will become part of each other.  We will...

Before God, I swear this creed.  My rifle and I are the defenders
of my country.  We are the masters of our enemy.  We are the
saviors of my life.

So be it, until victory is ours and there is no enemy, but
peace!"
 :sources (helm-org-rifle-get-sources-for-open-buffers))

;;;###autoload (autoload 'helm-org-rifle-current-buffer "helm-org-rifle" nil t)
(helm-org-rifle-defcommand
 "current-buffer" ()
 "Rifle through the current buffer."
 :sources (helm-org-rifle-get-source-for-buffer (current-buffer)))

;;;###autoload (autoload 'helm-org-rifle-files "helm-org-rifle" nil t)
(helm-org-rifle-defcommand
 "files" (&optional files)
 "Rifle through FILES, where FILES is a list of paths to Org files.
If FILES is nil, prompt with `helm-read-file-name'.  All FILES
are searched; they are not filtered with
`org-rifle-directories-filename-regexp'."
 :sources (--map (helm-org-rifle-get-source-for-file it) files)
 :let ((files (org-rifle--listify (or files
                                      (helm-read-file-name "Files: " :marked-candidates t))))
       (helm-candidate-separator " ")
       (helm-cleanup-hook (lambda ()
                            ;; Close new buffers if enabled
                            (when org-rifle-close-unopened-file-buffers
                              (if (= 0 helm-exit-status)
                                  ;; Candidate selected; close other new buffers
                                  (let ((candidate-source (helm-attr 'name (helm-get-current-source))))
                                    (dolist (source helm-sources)
                                      (unless (or (equal (helm-attr 'name source)
                                                         candidate-source)
                                                  (not (helm-attr 'new-buffer source)))
                                        (kill-buffer (helm-attr 'buffer source)))))
                                ;; No candidates; close all new buffers
                                (dolist (source helm-sources)
                                  (when (helm-attr 'new-buffer source)
                                    (kill-buffer (helm-attr 'buffer source))))))))))

;;;###autoload (autoload 'helm-org-rifle-sort-by-latest-timestamp "helm-org-rifle" nil t)
(helm-org-rifle-defcommand
 "sort-by-latest-timestamp" ()
 "Rifle through open buffers, sorted by latest timestamp."
 :transformer 'helm-org-rifle-transformer-sort-by-latest-timestamp
 :sources (helm-org-rifle-get-sources-for-open-buffers))

;;;###autoload (autoload 'helm-org-rifle-current-buffer-sort-by-latest-timestamp "helm-org-rifle" nil t)
(helm-org-rifle-defcommand
 "current-buffer-sort-by-latest-timestamp" ()
 "Rifle through the current buffer, sorted by latest timestamp."
 :transformer 'helm-org-rifle-transformer-sort-by-latest-timestamp
 :sources (helm-org-rifle-get-source-for-buffer (current-buffer)))

;;;###autoload
(defun helm-org-rifle-agenda-files ()
  "Rifle through Org agenda files."
  ;; This does not need to be defined with helm-org-rifle-defcommand because it calls helm-org-rifle-files which is.
  (interactive)
  (helm-org-rifle-files (org-agenda-files)))

;;;###autoload
(defun helm-org-rifle-directories (&optional directories toggle-recursion)
  "Rifle through Org files in DIRECTORIES.
DIRECTORIES may be a string or list of strings.  If DIRECTORIES
is nil, prompt with `helm-read-file-name'.  With prefix or
TOGGLE-RECURSION non-nil, toggle recursion from the default.
Files in DIRECTORIES are filtered using
`org-rifle-directories-filename-regexp'."
  (interactive)
  (let* ((recursive (if (or toggle-recursion current-prefix-arg)
                        (not org-rifle-directories-recursive)
                      org-rifle-directories-recursive))
         (directories (org-rifle--listify
                       (or directories
                           (-select 'f-dir? (helm-read-file-name "Directories: " :marked-candidates t)))))
         (files (-flatten (--map (f-files it
                                          (lambda (file)
                                            (s-matches? org-rifle-directories-filename-regexp (f-filename file)))
                                          recursive)
                                 directories))))
    (if files
        (helm-org-rifle-files files)
      (error "No org files found in directories: %s" (s-join " " directories)))))

;;;###autoload
(defun helm-org-rifle-org-directory ()
  "Rifle through Org files in `org-directory'."
  (interactive)
  (helm-org-rifle-directories (list org-directory)))

;;;;; Sources

(defun helm-org-rifle-get-source-for-buffer (buffer)
  "Return Helm source for BUFFER."
  (let ((source (helm-build-sync-source (buffer-name buffer)
                  :after-init-hook helm-org-rifle-after-init-hook
                  :candidates (lambda ()
                                (when (s-present? helm-pattern)
                                  (org-rifle--get-candidates-in-buffer (helm-attr 'buffer) helm-pattern)))
                  :candidate-transformer org-rifle-transformer
                  :match 'identity
                  :multiline helm-org-rifle-multiline
                  :volatile t
                  :action 'helm-org-rifle-actions
                  :keymap helm-org-rifle-map)))
    (helm-attrset 'buffer buffer source)
    source))

(defun helm-org-rifle-get-source-for-file (file)
  "Return Helm source for FILE.
If the file is not already in an open buffer, it will be opened
with `find-file-noselect'."
  (let ((buffer (org-find-base-buffer-visiting file))
        new-buffer source)
    (unless buffer
      (if (f-exists? file)
          (progn
            (setq buffer (find-file-noselect file))
            (setq new-buffer t))
        (error "File not found: %s" file)))
    (setq source (helm-org-rifle-get-source-for-buffer buffer))
    (helm-attrset 'new-buffer new-buffer source)
    source))

(defun helm-org-rifle-get-sources-for-open-buffers ()
  "Return list of sources configured for `helm-org-rifle'.
One source is returned for each open Org buffer."
  (mapcar 'helm-org-rifle-get-source-for-buffer
          (-select 'org-rifle-buffer-visible-p (org-buffer-list nil t))))

;;;;; Show entries

(defun helm-org-rifle--save-results ()
  "Save `helm-org-rifle' result in a `org-rifle' buffer.
In the spirit of `helm-grep-save-results'."
  (interactive)
  (helm-org-rifle--mark-all-candidates)
  (helm-exit-and-execute-action 'helm-org-rifle--show-candidates))

(defun helm-org-rifle--mark-all-candidates ()
  "Mark all candidates in Helm buffer.
`helm-mark-all' only marks in the current source, not all
sources, so we do it ourselves."
  ;; Based on `helm-mark-all'

  ;; FIXME: [2017-04-09 Sun 12:54] Latest Helm commit adds arg to
  ;; `helm-mark-all' to mark in all sources.
  (with-helm-window
    (let ((follow (if (helm-follow-mode-p (helm-get-current-source)) 1 -1)))
      (helm-follow-mode -1)  ; Disable follow so we don't jump to every candidate
      (save-excursion
        (goto-char (point-min))
        ;; Mark first candidate
        (forward-line 1)  ; Skip header line
        (helm-mark-current-line)
        (helm-make-visible-mark)
        (while (ignore-errors (goto-char (next-single-property-change (point) 'helm-candidate-separator)))
          ;; Mark rest of candidates
          (forward-line 1)
          (helm-mark-current-line)
          (helm-make-visible-mark)))
      (helm-follow-mode follow))))

(defun helm-org-rifle--show-candidates (&optional candidates)
  "Show CANDIDATES (or, if nil, all candidates marked in Helm).
If one candidate is given, the default
`helm-org-rifle-show-entry-function' will be used.  If multiple
candidates, `helm-org-rifle--show-entries-as-occur' will be
used."
  (let ((candidates (or (helm-org-rifle--get-marked-candidates)
                        candidates)))
    (pcase (safe-length candidates)
      (1 (helm-org-rifle-show-entry candidates))
      (_ (helm-org-rifle--show-entries-as-occur candidates)))))

(defun helm-org-rifle--get-marked-candidates ()
  "Return list of all marked candidates in Helm.
`helm-marked-candidates' only returns results from the current
source, so we must gather them manually."
  ;; Based on `helm-revive-visible-mark'

  ;; FIXME: [2017-04-09 Sun 11:02] Current Helm version does this with
  ;; an arg to `helm-marked-candidates', but this should be faster
  ;; since it does a lot less behind the scenes.
  (with-current-buffer helm-buffer
    (save-excursion
      (cl-loop for o in helm-visible-mark-overlays
               collect (overlay-get o 'real) into res
               finally return (nreverse res)))))

(defun helm-org-rifle--show-entries-as-occur (entries)
  "Display a buffer showing ENTRIES.
ENTRIES is a list of (BUFFER . NODE-BEG) pairs from the REAL of
the (DISPLAY . REAL) pair from
`org-rifle--get-candidates-in-buffer'."
  (let ((inhibit-read-only t))
    (with-current-buffer (org-rifle--prepare-results-buffer)
      (erase-buffer)
      (cl-loop for (buffer . node-beg) in entries
               for text = (org-rifle--get-entry-text buffer node-beg :include-heading t :full-path org-rifle-show-path)
               do (progn (add-text-properties 0 (length text) (list :buffer buffer :node-beg node-beg) text)
                         (insert org-rifle-separator)
                         (insert text)))
      (org-rifle-highlight-matches-in-buffer (current-buffer) helm-input))))

(defun helm-org-rifle-transformer-sort-by-latest-timestamp (candidates)
  "Sort CANDIDATES by latest timestamp in each candidate in SOURCE."
  (with-current-buffer (helm-attr 'buffer) ; This is necessary or it will try to use the "*helm*" buffer instead of the source.
    ;; FIXME: This caused a lot of hair-pulling when adding the occur
    ;; code, because the occur code doesn't use this transformer and
    ;; so wasn't running the timestamp-getting function in the right
    ;; buffer--it was running it in the minibuffer.  It would be good
    ;; to make them use a common format so they could always use the
    ;; transformer, but that wouldn't be as good for performance,
    ;; because then the transformer would ALWAYS have to run.  Maybe
    ;; it's worth it...
    (->> candidates
         (helm-org-rifle-transform-candidates-to-list-of-nodes)
         (org-rifle-add-timestamps-to-nodes)
         (org-rifle-sort-nodes-by-latest-timestamp)
         (helm-org-rifle-transform-list-of-nodes-to-candidates))))

(defun helm-org-rifle-transform-candidates-to-list-of-nodes (candidates)
  "Transform Helm-style CANDIDATES list to list of plists."
  (--map (list :node-beg (cadr it)
               :text (car it))
         candidates))

(defun helm-org-rifle-transform-list-of-nodes-to-candidates (nodes)
  "Transform NODES to Helm-style candidates.
NODES should be a list of node plists."
  (--map (list (plist-get it :text)
               (plist-get it :node-beg))
         nodes))

(defun helm-org-rifle-show-entry (candidate)
  "Show CANDIDATE using the default function."
  (funcall helm-org-rifle-show-entry-function candidate))

(defun helm-org-rifle-show-entry-in-real-buffer (candidate)
  "Show CANDIDATE in its real buffer."
  (helm-attrset 'new-buffer nil)  ; Prevent the buffer from being cleaned up
  (-let (((buffer . pos) candidate))
    (switch-to-buffer buffer)
    (goto-char pos))
  (org-show-entry))

(defun helm-org-rifle-show-entry-in-indirect-buffer (candidate)
  "Show CANDIDATE in an indirect buffer."
  (-let (((buffer . pos) candidate)
         (original-buffer (current-buffer)))
    (helm-attrset 'new-buffer nil)  ; Prevent the buffer from being cleaned up
    (with-current-buffer buffer
      (save-excursion
        (goto-char pos)
        (org-tree-to-indirect-buffer)
        (unless (equal original-buffer (car (window-prev-buffers)))
          ;; The selected bookmark was in a different buffer.  Put the
          ;; non-indirect buffer at the bottom of the prev-buffers list
          ;; so it won't be selected when the indirect buffer is killed.
          (set-window-prev-buffers nil (append (cdr (window-prev-buffers))
                                               (car (window-prev-buffers)))))))))

(defun helm-org-rifle-show-entry-in-indirect-buffer-map-action ()
  "Exit Helm buffer and call `helm-org-rifle-show-entry-in-indirect-buffer' with selected candidate."
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-org-rifle-show-entry-in-indirect-buffer)))

(defun helm-org-rifle--clock-in (candidate)
  "Clock into CANDIDATE."
  (-let (((buffer . pos) candidate))
    (with-current-buffer buffer
      (goto-char pos)
      (org-clock-in))))

(defun helm-org-rifle-set-input-idle-delay ()
  "Set `helm-input-idle-delay' in Helm buffer."
  (with-helm-buffer
    (setq-local helm-input-idle-delay helm-org-rifle-input-idle-delay)))

;;;; Footer

(provide 'helm-org-rifle)

;;; helm-org-rifle.el ends here
