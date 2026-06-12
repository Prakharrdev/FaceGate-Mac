# ML Models

This directory will contain the Core ML face embedding model (`FaceEmbedding.mlpackage`) 
in Phase 2 of development.

## How to add the model

1. Run `Scripts/convert_model.py` to convert a pre-trained MobileFaceNet model to Core ML format
2. Place the resulting `FaceEmbedding.mlpackage` in this directory
3. XcodeGen will automatically include it as a resource in the build
