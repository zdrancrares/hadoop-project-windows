import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.URI;
import java.util.*;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.FSDataInputStream;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.Reducer;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.input.FileSplit;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;

public class InvertedIndex {

    // MAPPER
    // Input  key  : byte offset (LongWritable)
    // Input  value: text of the line
    // Output key  : "word\tfilename"
    // Output value: line number (1-based, as Text)
    public static class IndexMapper
            extends Mapper<LongWritable, Text, Text, Text> {

        private final Set<String> stopWords = new HashSet<>();
        private static final String DELIMITERS =
                "\"\',.()?![]#$*-;:_+/\\<>@%& \t\r\n0123456789";

        private long lineNumber = 0;
        private String fileName  = "";

        @Override
        protected void setup(Context context)
                throws IOException, InterruptedException {

            lineNumber = 0;

            FileSplit split = (FileSplit) context.getInputSplit();
            fileName = split.getPath().getName();

            URI[] cacheFiles = context.getCacheFiles();
            if (cacheFiles != null) {
                for (URI uri : cacheFiles) {
                    Path p = new Path(uri.getPath());
                    if (p.getName().equals("stopwords.txt")) {
                        FileSystem fs = FileSystem.get(context.getConfiguration());
                        try (FSDataInputStream in = fs.open(p);
                             BufferedReader br =
                                     new BufferedReader(new InputStreamReader(in))) {
                            String line;
                            while ((line = br.readLine()) != null) {
                                for (String w : line.trim()
                                        .toLowerCase()
                                        .split("\\s+")) {
                                    if (!w.isEmpty()) stopWords.add(w);
                                }
                            }
                        }
                        break;
                    }
                }
            }
        }

        @Override
        public void map(LongWritable key, Text value, Context context)
                throws IOException, InterruptedException {

            lineNumber++;

            StringTokenizer itr =
                    new StringTokenizer(value.toString(), DELIMITERS);
            while (itr.hasMoreTokens()) {
                String token = itr.nextToken().toLowerCase();
                if (token.length() < 2)            continue;
                if (stopWords.contains(token))     continue;

                context.write(
                        new Text(token + "\t" + fileName),
                        new Text(String.valueOf(lineNumber))
                );
            }
        }
    }

    // REDUCER
    // Input  key   : "word\tfilename"
    // Input  values: iterable of line-number strings
    // Output key   : word
    // Output value : "(filename, line N, line M, ...) (...) ..."
    public static class IndexReducer
            extends Reducer<Text, Text, Text, Text> {

        private String        lastWord = null;
        private String        lastFile = null;
        private List<Integer> lineNums = new ArrayList<>();
        private StringBuilder postings = new StringBuilder();

        @Override
        public void reduce(Text key, Iterable<Text> values, Context context)
                throws IOException, InterruptedException {

            String[] parts = key.toString().split("\t", 2);
            String word = parts[0];
            String file = parts.length > 1 ? parts[1] : "unknown";

            // New word: emit accumulated postings for previous word
            if (!word.equals(lastWord)) {
                if (lastWord != null) {
                    appendFile();
                    emit(context);
                }
                lastWord = word;
                lastFile = null;
                postings.setLength(0);
            }

            // New file within the same word
            if (!file.equals(lastFile)) {
                if (lastFile != null) appendFile();
                lastFile = file;
                lineNums.clear();
            }

            Set<Integer> seen = new HashSet<>(lineNums);
            for (Text v : values) {
                try {
                    int ln = Integer.parseInt(v.toString());
                    if (seen.add(ln)) lineNums.add(ln);
                } catch (NumberFormatException ignored) { }
            }
        }

        private void appendFile() {
            if (lastFile == null || lineNums.isEmpty()) return;
            Collections.sort(lineNums);
            postings.append("(").append(lastFile);
            for (int ln : lineNums) postings.append(", line ").append(ln);
            postings.append(") ");
            lineNums.clear();
        }

        private void emit(Context context)
                throws IOException, InterruptedException {
            context.write(new Text(lastWord),
                    new Text(postings.toString().trim()));
        }

        @Override
        protected void cleanup(Context context)
                throws IOException, InterruptedException {
            if (lastWord != null) {
                appendFile();
                emit(context);
            }
        }
    }

    // DRIVER
    public static void main(String[] args) throws Exception {

        String stopWordsHdfsPath = "stopwords.txt";
        List<String> rest = new ArrayList<>();
        for (int i = 0; i < args.length; i++) {
            if ("--stopwords".equals(args[i]) && i + 1 < args.length) {
                stopWordsHdfsPath = args[++i];
            } else {
                rest.add(args[i]);
            }
        }

        if (rest.size() < 2) {
            System.err.println(
                    "Usage: InvertedIndex [--stopwords <hdfs-path>] " +
                    "<input-dir> <output-dir>");
            System.exit(2);
        }

        Configuration conf = new Configuration();
        Job job = Job.getInstance(conf, "Inverted Index");
        job.setJarByClass(InvertedIndex.class);

        job.addCacheFile(new URI(stopWordsHdfsPath));

        job.setMapperClass(IndexMapper.class);
        job.setReducerClass(IndexReducer.class);

        job.setMapOutputKeyClass(Text.class);
        job.setMapOutputValueClass(Text.class);
        job.setOutputKeyClass(Text.class);
        job.setOutputValueClass(Text.class);

        job.setNumReduceTasks(1);

        FileInputFormat.addInputPath(job, new Path(rest.get(0)));
        FileOutputFormat.setOutputPath(job, new Path(rest.get(1)));

        System.exit(job.waitForCompletion(true) ? 0 : 1);
    }
}
