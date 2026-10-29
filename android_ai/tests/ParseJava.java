import javax.tools.*;
import com.sun.source.util.JavacTask;
import java.util.*;
/** Parses the actual plugin source without pretending missing Android types are present. */
public class ParseJava {
    public static void main(String[] paths) throws Exception {
        JavaCompiler compiler = ToolProvider.getSystemJavaCompiler();
        if (compiler == null) throw new IllegalStateException("Java compiler module unavailable");
        DiagnosticCollector<JavaFileObject> diagnostics = new DiagnosticCollector<>();
        try (StandardJavaFileManager files = compiler.getStandardFileManager(diagnostics, null, null)) {
            JavacTask task = (JavacTask) compiler.getTask(null, files, diagnostics,
                    Arrays.asList("-proc:none", "--release", "17"), null, files.getJavaFileObjects(paths));
            task.parse();
            for (Diagnostic<?> diagnostic : diagnostics.getDiagnostics()) {
                System.out.println(diagnostic);
                if (diagnostic.getKind() == Diagnostic.Kind.ERROR) throw new AssertionError("Java syntax error");
            }
        }
        System.out.println("PASS: Java 17 parsing only; Android/ORT type resolution and native runtime are untested");
    }
}
