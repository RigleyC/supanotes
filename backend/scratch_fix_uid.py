import os

for root, _, files in os.walk(r'd:\projects\supanotes\backend\internal'):
    for file in files:
        if file.endswith('.go'):
            path = os.path.join(root, file)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            changed = False
            if 'auth.UUIDFromString' in content or 'auth.UUIDToString' in content:
                content = content.replace('auth.UUIDFromString', 'uid.UUIDFromString')
                content = content.replace('auth.UUIDToString', 'uid.UUIDToString')
                changed = True
                
                if '"github.com/RigleyC/supanotes/pkg/uid"' not in content:
                    content = content.replace(
                        '"github.com/labstack/echo/v4"', 
                        '"github.com/RigleyC/supanotes/pkg/uid"\n\t"github.com/labstack/echo/v4"'
                    )
            
            if '"sort"' in content and file == 'service.go' and 'search' in root:
                content = content.replace('\n\t"sort"\n', '\n')
                changed = True

            if changed:
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f"Fixed {path}")
