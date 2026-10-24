---
id: tool_descriptions.read
description: Description of the read tool schema
vars: [maxLines, maxKb]
---
Read a text file of the workspace, or an image when the model accepts images. Lines are numbered "<n>| <text>". Output is limited to {{maxLines}} lines or {{maxKb}} KB; use offset and limit to read a part of a long file.
