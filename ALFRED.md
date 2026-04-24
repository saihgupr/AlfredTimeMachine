# Setting up Alfred with Retro 🎩

You can integrate Retro into Alfred as a **Universal Action** or a **File Action**. This allows you to select a file in Finder, trigger Alfred, and instantly see restoration options.

## 1. Create a new Alfred Workflow
1. Open Alfred Settings -> Workflows.
2. Click the `+` button -> Blank Workflow. Name it "Retro Restore".

## 2. Add a Universal Action
1. Right-click in the workflow canvas -> **Inputs** -> **Universal Action**.
2. Set "Action Name" to `Retro: List Versions`.
3. Set "Types" to `Files`.

## 3. Add a Script Filter
1. Right-click -> **Inputs** -> **Script Filter**.
2. Connect the Universal Action to this Script Filter.
3. In the Script Filter settings:
   - Language: `/bin/bash`
   - Script:
     ```bash
     # $1 is the file path from the Universal Action
     /Users/username/Desktop/untitled\ folder/retro list "$1" --alfred
     ```

## 4. Add the Restore Action
1. Right-click -> **Actions** -> **Run Script**.
2. Connect the Script Filter to this Run Script.
3. In the Run Script settings:
   - Language: `/bin/bash`
   - Script:
     ```bash
     # {query} is the index from the script filter
     # We need the original file path. You can pass it through variables in Alfred 
     # or use this logic:
     /Users/username/Desktop/untitled\ folder/retro restore "$original_file" --index "$1"
     ```

*(Note: In a more advanced Alfred setup, you'd store the selected file path in an Alfred variable named `original_file` in step 2/3 so the restore script knows what file to target.)*

## 5. Add a Notification (Optional)
1. Right-click -> **Outputs** -> **Post Notification**.
2. Connect the Run Script to this. Set the title to "File Restored" and text to "Check for the .restored file".
