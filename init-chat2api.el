;;; init-aider.el --- Aider and gptel configuration -*- lexical-binding: t; -*-

;;; Comentary:
;; Integration for using Chat2API with aidermacs and gptel.

;;; Code:

(defvar my-llm-model-list '("DeepSeek-V3.2" "DeepSeek-Search" "DeepSeek-R1" "DeepSeek-R1-Search" "Kimi-K2.5")
  "List of models to choose from.")

(defvar my-aider-model "DeepSeek-Search") ; Default Model for Aider

(use-package gptel
  :ensure t
  :config
  (setq gptel-model "DeepSeek-Search") ; Default model for gptel
  (setq gptel-backend
        (gptel-make-openai "Chat2API" ; Name of the backend in Emacs
          :host "localhost:5005"
          :protocol "http"            ; Usually "http" for localhost
          :key "dummy"
          :endpoint "/v1/chat/completions" ; Standard endpoint path
          :stream t
          :models my-llm-model-list))) ; Using the shared list here

(use-package aidermacs
  :bind ("C-c a" . aidermacs-transient-menu)
  :config
  (setq aidermacs-args
        (list "--no-show-model-warnings"
              "--model"
              (format "openai/%s" my-aider-model)))

  (setenv "OPENAI_API_BASE" "http://localhost:5005/v1/")
  (setenv "OPENAI_API_KEY" "dummy")

  (setq aidermacs-use-vterm nil)  ; Uses comint instead
  (setq aidermacs-auto-commits nil) ; Reduce background operations
  (setq aidermacs-auto-test nil)    ; Unless you need it
  (setq read-process-output-max (* 1024 1024)) ; Increase for streaming
  )

(add-hook 'aidermacs-comint-mode-hook
          (lambda ()
            (visual-line-mode 1)      ; Enable soft wrapping
            (setq word-wrap t)        ; Break at word boundaries, not middle of words
            (setq truncate-lines nil) ; Ensure horizontal scrolling is off
            ))

(defun my-aider-choose-model ()
  "Interactively select a model and update aidermacs-args."
  (interactive)
  (let ((choice (completing-read "Select Aider Model: " my-llm-model-list))) ; Using shared list
    (setq my-aider-model choice)
    ;; Update the actual args list used by the package
    (setq aidermacs-args
          (list "--no-show-model-warnings"
                "--model"
                (format "openai/%s" my-aider-model)))
    (message "Aider model set to: %s" choice)))

(with-eval-after-load 'aidermacs
  (require 'transient)

  ;; Add the model switcher to the transient menu
  ;; We bind it to '-m' within the C-c a menu
  (transient-append-suffix 'aidermacs-transient-menu [0 -1]
    ["Model Settings"
     ("-m" "Switch Model" my-aider-choose-model)]))



(provide 'init-chat2api)
;;; init-aider.el ends here
