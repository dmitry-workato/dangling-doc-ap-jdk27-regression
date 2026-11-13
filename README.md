# javac 27: `-Xlint:dangling-doc-comments` warnings are silently dropped when annotation processing runs

## Summary

Since JDK 27, javac does not report `dangling-doc-comments` warnings if any annotation
processor runs during the compilation. The same compilation on JDK 23–26 reports them.
No diagnostic of any kind is emitted — the warning is lost, not suppressed by an option.

Because the warning disappears rather than being downgraded, a build using
`-Xlint:all -Werror` (together with any annotation processor, which is the normal case for
Lombok / Immutables / Spring / Dagger / AutoValue users) compiles successfully on JDK 27
and fails on JDK 26 and earlier for the same sources.

## Affected versions

Tested with the files in this directory (`./run.sh <JAVA_HOME>...`):

| javac | without processor | with a do-nothing processor |
|---|---|---|
| 21.0.8, 22.0.2 | warns (only with the explicit `-Xlint:dangling-doc-comments`; the category is not in `-Xlint:all` yet) | warns |
| 23.0.1 | warns | warns |
| 24.0.2 | warns | warns |
| 25.0.5 | warns | warns |
| 26 | warns | warns |
| **27.0.0.0+35 (Temurin)** | warns | **nothing** |
| **27.0.1.0.3 (SapMachine)** | warns | **nothing** |

## Reproducer

Files: `Plain.java` (input), `NoopProcessor.java` (a processor whose `process` does nothing
and claims nothing), `run.sh`.

```java
class Plain {
    /** first */
    /** second */
    void m() {}
}
```

```sh
javac -d out/proc NoopProcessor.java

# (a) no annotation processing
javac -d out/a -Xlint:dangling-doc-comments Plain.java

# (b) identical, plus a processor that does nothing
javac -d out/b -Xlint:dangling-doc-comments \
      -processorpath out/proc -processor NoopProcessor Plain.java
```

### Expected

(a) and (b) both print:

```
Plain.java:2: warning: [dangling-doc-comments] documentation comment is not attached to any declaration
    /** first */
    ^
1 warning
```

### Actual on JDK 27

(a) prints the warning; (b) prints nothing and exits 0.

## Additional observations

* Not specific to the shape of the declaration: it reproduces with a plain method as above
  and with Javadoc written on record components.
* It is enough for a processor to be *run*; it need not claim anything or generate anything.
  `-proc:none`, or an empty `-processorpath`, or `-proc:full` with no processor available,
  all restore the warning.
* Warnings for sources **generated** by the processor are lost in the same way: a processor
  that emits a file containing a dangling doc comment produces no warning for it either.
* Other lint warnings raised by the parser are not affected: `-Xlint:text-blocks`
  (inconsistent white space indentation) is still reported with a processor present.
  The affected category appears to be the one that is parked for retroactive
  `@SuppressWarnings` evaluation.

## Possible cause (unverified)

`dangling-doc-comments` is raised from `JavacParser.reportDanglingDocComment` →
`Scanner.lintWarning` → `Log`, and `Log.DiagnosticHandler.report` parks it via
`addLintWaiter(currentSourceFile(), diag)` because the applicable `Lint` at that position is
not yet known (`@SuppressWarnings` must be able to suppress it retroactively, see
JDK-8354447).

`Log.DiagnosticHandler.flushLintWaiters()` then drops every parked diagnostic whose source
file the `LintMapper` does not recognise:

```java
// Is the source file no longer recognized? If so, discard warnings (e.g., this can happen with JShell)
JavaFileObject sourceFile = entry.getKey();
if (!lintMapper.isKnown(sourceFile))
    return true;
```

`LintMapper` learns about a file in `JavaCompiler.parse` (`startParsingFile` /
`finishParsingFile`) and is a per-`Context` component, while annotation processing continues
each round in a new `Context` with the already-parsed trees. If the round's `LintMapper`
never saw the parse, `isKnown` is false and the parked warnings are discarded silently.

## Environment

macOS (Darwin 25.6.0, aarch64). Reproduced with Temurin 27.0.0+35 and SapMachine 27.0.1.0.3;
not reproducible with Temurin 23/24/25/26.
