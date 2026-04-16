;;; init-aider.el --- Aider and gptel configuration -*- lexical-binding: t; -*-

;;; Comentary:
;; Integration for using Chat2API with aidermacs and gptel.

;;; Code:

;; 1. Global AI State (The "Brain" for both gptel and aidermacs)
(defvar my-llm-model-list '("DeepSeek-V3.2" "DeepSeek-Search" "DeepSeek-R1" "DeepSeek-R1-Search" "Kimi-K2.5")
  "List of models to choose from.")

(defvar my-aider-model "DeepSeek-V3.2")

(defvar my-ai-proxy-settings '((web_search . :json-false)
                               (deep_thinking . :json-false))
  "Shared state for AI proxy features (Web Search and Deep Thinking).")

;; 2. GPTel Configuration
(use-package gptel
  :ensure t
  :config
  (setq gptel-model "DeepSeek-V3.2")
  (setq gptel-backend
        (gptel-make-openai "Chat2API"
          :host "localhost:5005"
          :protocol "http"
          :key "dummy"
          :endpoint "/v1/chat/completions"
          :stream t
          :models '(DeepSeek-V3.2 DeepSeek-Search DeepSeek-R1 Kimi-K2.5)
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

  ;; Define GPTel specific infixes using the shared class
  (require 'transient)
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

;; 3. Aidermacs Configuration
(use-package aidermacs
  :bind ("C-c a" . aidermacs-transient-menu)
  :config
  (setq aidermacs-args
        (list "--no-show-model-warnings"
              "--model-settings-file" ".aider.proxy.yml"
              "--model" (format "openai/%s" (or (bound-and-true-p my-aider-model) "DeepSeek-V3.2"))))

  (setenv "OPENAI_API_BASE" "http://localhost:5005/v1/")
  (setenv "OPENAI_API_KEY" "dummy")

  (setq aidermacs-use-vterm nil)
  (setq aidermacs-auto-commits nil)
  (setq aidermacs-auto-test nil)
  (setq read-process-output-max (* 1024 1024))

  (add-hook 'aidermacs-comint-mode-hook
            (lambda ()
              (visual-line-mode 1)
              (setq word-wrap t)
              (setq truncate-lines nil)))

  ;; Model Settings Writer using shared settings variable
  (defun my-aidermacs-write-config ()
    "Generate .aider.proxy.yml using the shared my-ai-proxy-settings."
    (interactive)
    (let* ((root (or (vc-root-dir) (locate-dominating-file default-directory ".git") default-directory))
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
      (message "Aider proxy settings synced: %s" proxy-file)))

  (my-aidermacs-write-config))

;; 4. Aidermacs Transient Integration
(with-eval-after-load 'aidermacs
  (require 'transient)

  (defun my-aider-choose-model ()
    "Interactively select a model and update aidermacs-args."
    (interactive)
    (let ((choice (completing-read "Select Aider Model: " my-llm-model-list)))
      (setq my-aider-model choice)
      (setq aidermacs-args
            (list "--no-show-model-warnings"
                  "--model-settings-file" ".aider.proxy.yml"
                  "--model" (format "openai/%s" choice)))
      (my-aidermacs-write-config)
      (message "Aider model set to: %s" choice)))

  ;; Shared toggle class for Aider menu
  (defclass my-aidermacs-infix-toggle (my-ai-infix-toggle) ()
    "Toggle that updates the proxy-specific model settings file.")

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
