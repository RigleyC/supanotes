import os

for root, _, files in os.walk(r'd:\projects\supanotes\backend\internal'):
    for file in files:
        if file.endswith('.go'):
            path = os.path.join(root, file)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            changed = False
            # remove unused auth import
            if '"github.com/RigleyC/supanotes/internal/auth"' in content and 'auth.' not in content:
                content = content.replace('\t"github.com/RigleyC/supanotes/internal/auth"\n', '')
                changed = True

            if changed:
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f"Fixed {path}")
