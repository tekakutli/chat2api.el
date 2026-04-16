# chat2api.el

A streamlined Emacs configuration to set up **aidermacs** and **gptel** to use the [xiaoY233/Chat2API](https://github.com/xiaoY233/Chat2API) proxy. 

## Instructions

1.  **Set up Chat2API first**
Add a provider, then at Proxy Setting set the port at 5005, and then `Start Proxy` in the Dashboard.

2.  **Clone and then add to your `config.el`:**

    ```elisp
    (add-to-list 'load-path "/path/to/chat2api.el/")
    (require 'init-chat2api)
    ```

## Requirements

  * I'm using Doom so I just enabled the 'llm' flag at init.el and then I `(package! aidermacs)` too.

-----

### Pro-Tip

To change the available models, simply edit the `my-llm-model-list` variable inside `init-chat2api.el`. The `aidermacs` transient menu will update automatically.
