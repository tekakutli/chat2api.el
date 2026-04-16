;;; init-aider.el --- Aider and gptel configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Integration for using Chat2API with aidermacs and gptel.

;;; Code:

;; ==========================================
;; 1. GLOBAL AI STATE & SMART LOGIC
;; ==========================================

;; Qwen: https://www.qianwen.com/
(defvar my-llm-model-list '("DeepSeek-V3.2" "DeepSeek-Search" "DeepSeek-R1" "DeepSeek-R1-Search" "Kimi-K2.5" "Qwen3.5-Plus")
  "List of models to choose from.")

(defvar my-aider-model "DeepSeek-V3.2")

(defvar my-ai-proxy-settings '((web_search . :json-false)
                               (deep_thinking . :json-false))
  "Shared state for AI proxy features (Web Search and Deep Thinking).")

(defun my-ai-apply-model-side-effects (model-name)
  "Update proxy settings based on the chosen MODEL-NAME.
Resets to defaults unless the model matches a specific pattern."
  (pcase model-name
    ((or "DeepSeek-Search" "DeepSeek-R1-Search" "Kimi-K2.5")
     (setf (alist-get 'web_search my-ai-proxy-settings) t)
     (setf (alist-get 'deep_thinking my-ai-proxy-settings) :json-false))
    ((or "DeepSeek-R1" "DeepSeek-R1-Search")
     (setf (alist-get 'deep_thinking my-ai-proxy-settings) t))
    (_ ; Default: reset toggles for base models
     (setf (alist-get 'web_search my-ai-proxy-settings) :json-false)
     (setf (alist-get 'deep_thinking my-ai-proxy-settings) :json-false)))

  ;; Sync the Aider config file immediately if the function exists
  (when (fboundp 'my-aidermacs-write-config)
    (my-aidermacs-write-config)))

;; ==========================================
;; 2. GPTEL CONFIGURATION
;; ==========================================

(use-package gptel
  :ensure t
  :config
  (setq gptel-model (intern "DeepSeek-V3.2"))
  (setq gptel-backend
        (gptel-make-openai "Chat2API"
          :host "localhost:5005"
          :protocol "http"
          :key "dummy"
          :endpoint "/v1/chat/completions"
          :stream t
          :models (mapcar #'intern my-llm-model-list)
          :header (lambda ()
                    (let ((headers nil))
                      (when (eq (alist-get 'web_search my-ai-proxy-settings) t)
                        (push '("X-Web-Search" . "true") headers))
                      (when (eq (alist-get 'deep_thinking my-ai-proxy-settings) t)
                        (push '("X-Reasoning-Effort" . "high") headers))
                      headers))))

  ;; Generic Infix Class for shared toggles
  (with-eval-after-load 'transient
    (defclass my-ai-infix-toggle (transient-infix)
      ((param-name :initarg :param-name :initform nil))
      "Generic infix for toggling keys in my-ai-proxy-settings.")

    (cl-defmethod transient-infix-read ((obj my-ai-infix-toggle))
      (let* ((param (oref obj param-name))
             (current (alist-get param my-ai-proxy-settings))
             (new-val (if (eq current t) :json-false t)))
        (setf (alist-get param my-ai-proxy-settings) new-val)
        new-val))

    (cl-defmethod transient-format-value ((obj my-ai-infix-toggle))
      (let* ((param (oref obj param-name))
             (val (alist-get param my-ai-proxy-settings)))
        (if (eq val t)
            (propertize "on" 'face 'transient-value)
          (propertize "off" 'face 'transient-inactive-value)))))

  ;; gptel Specific Infixes
  (transient-define-infix my-gptel-web-search-infix ()
    :class 'my-ai-infix-toggle
    :param-name 'web_search
    :key "-w"
    :description "Web Search")

  (transient-define-infix my-gptel-deep-thinking-infix ()
    :class 'my-ai-infix-toggle
    :param-name 'deep_thinking
    :key "-t"
    :description "Deep Thinking")

  ;; Inject into gptel menu
  (advice-add 'gptel-menu :around
              (lambda (orig-fun &rest args)
                (condition-case nil
                    (progn
                      (transient-append-suffix 'gptel-menu 'gptel--infix-variable-scope
                        '("-w" "Web Search" my-gptel-web-search-infix))
                      (transient-append-suffix 'gptel-menu 'my-gptel-web-search-infix
                        '("-t" "Deep Thinking" my-gptel-deep-thinking-infix)))
                  (error nil))
                (apply orig-fun args))))

;; ==========================================
;; 3. AIDERMACS CONFIGURATION
;; ==========================================

(use-package aidermacs
  :bind ("C-c a" . aidermacs-transient-menu)
  :config
  ;; Global environment setup
  (setenv "OPENAI_API_BASE" "http://localhost:5005/v1")
  (setenv "OPENAI_API_KEY" "dummy")

  ;; Initial args setup (Updated with explicit proxy flags)
  (setq aidermacs-args
        (list "--no-show-model-warnings"
              "--model-settings-file" ".aider.proxy.yml"
              "--openai-api-base" "http://localhost:5005/v1"
              "--api-key" "openai=dummy"
              "--model" (format "openai/%s" (or (bound-and-true-p my-aider-model) "DeepSeek-V3.2"))))

  (setq aidermacs-use-vterm nil)
  (setq aidermacs-auto-commits nil)
  (setq aidermacs-auto-test nil)
  (setq read-process-output-max (* 1024 1024))

  ;; UI & Line Wrap
  (add-hook 'aidermacs-comint-mode-hook
            (lambda ()
              (visual-line-mode 1)
              (setq word-wrap t)
              (setq truncate-lines nil)))

  ;; Dedicated Model Settings Writer (Pure Elisp, No Shell)
  (defun my-aidermacs-write-config ()
    "Generate .aider.proxy.yml based on current shared settings."
    (interactive)
    (let* ((root (or (vc-root-dir)
                     (locate-dominating-file default-directory ".git")
                     default-directory))
           (root-path (expand-file-name (if (stringp root) root default-directory)))
           (proxy-file (expand-file-name ".aider.proxy.yml" root-path))
           (web-search (eq (alist-get 'web_search my-ai-proxy-settings) t))
           (thinking   (eq (alist-get 'deep_thinking my-ai-proxy-settings) t)))

      (if (or web-search thinking)
          (with-temp-file proxy-file
            (insert "- name: aider/extra_params\n")
            (insert "  extra_params:\n")
            (insert "    extra_headers:\n")
            (when web-search (insert "      X-Web-Search: \"true\"\n"))
            (when thinking   (insert "      X-Reasoning-Effort: \"high\"\n")))
        (when (file-exists-p proxy-file)
          (delete-file proxy-file)))
      (message "Aider proxy synced at: %s" proxy-file)))

  (my-aidermacs-write-config))

;; ==========================================
;; 4. AIDER TRANSIENT & MODEL CHOOSER
;; ==========================================

(with-eval-after-load 'aidermacs
  (require 'transient)

  (defun my-aider-choose-model ()
    "Select model and apply side-effects (auto-toggles)."
    (interactive)
    (let ((choice (completing-read "Select Aider Model: " my-llm-model-list)))
      (setq my-aider-model choice)
      ;; This triggers the side-effects AND the file write
      (my-ai-apply-model-side-effects choice)
      ;; Refresh environment and args to ensure local-only connection
      (setenv "OPENAI_API_BASE" "http://localhost:5005/v1")
      (setenv "OPENAI_API_KEY" "dummy")
      (setq aidermacs-args
            (list "--no-show-model-warnings"
                  "--model-settings-file" ".aider.proxy.yml"
                  "--openai-api-base" "http://localhost:5005/v1"
                  "--api-key" "openai=dummy"
                  "--model" (format "openai/%s" choice)))
      (message "Aider set to: %s" choice)))

  ;; Specialized Aider Toggles (triggers file write on toggle)
  (defclass my-aidermacs-infix-toggle (my-ai-infix-toggle) ()
    "Toggle that updates the proxy-specific config file.")

  (cl-defmethod transient-infix-set ((obj my-aidermacs-infix-toggle) value)
    (cl-call-next-method obj value)
    (my-aidermacs-write-config))

  (transient-define-infix my-aidermacs-web-search ()
    :class 'my-aidermacs-infix-toggle
    :param-name 'web_search
    :key "-w"
    :description "Web Search")

  (transient-define-infix my-aidermacs-deep-thinking ()
    :class 'my-aidermacs-infix-toggle
    :param-name 'deep_thinking
    :key "-t"
    :description "Deep Thinking")

  (transient-append-suffix 'aidermacs-transient-menu [0 -1]
    ["Aider & Proxy Settings"
     ("-m" "Switch Model"        my-aider-choose-model)
     ("-w" "Web Search"          my-aidermacs-web-search)
     ("-t" "Deep Thinking"       my-aidermacs-deep-thinking)
     ("-u" "Force Update Proxy"  my-aidermacs-write-config)]))


(provide 'init-chat2api)
;;; init-aider.el ends here
