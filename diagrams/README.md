# Diagram Assets

The source of truth for each network image is the `diagram.dot` file in its
chapter directory. Run `bash scripts/generate-diagrams.sh` after changing a
source diagram. The script renders both `diagram.svg` and `diagram.png` with
Graphviz.

Solid edges are active paths, dashed edges are blocked or not-yet-introduced
paths, and dotted edges represent control, observation, name-resolution, or
process relationships. The same legend appears in every image.
