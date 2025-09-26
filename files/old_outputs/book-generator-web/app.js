const express = require('express');
const bodyParser = require('body-parser');
const { exec, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const app = express();
const port = 3000;

// Middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));

// Routes
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// API endpoint to generate a book
app.post('/api/generate-book', (req, res) => {
    const { topic, genre, audience, outlineOnly, model, temperature, minWords, maxWords, style, tone, delay } = req.body;
    
    if (!topic || !genre || !audience) {
        return res.status(400).json({ success: false, message: 'Missing required fields' });
    }
    
    // Build command with parameters
    let args = [
        '../full_book_generator.sh',
        `"${topic}"`,
        `"${genre}"`,
        `"${audience}"`
    ];
    
    // Add optional parameters
    if (outlineOnly) args.push('--outline-only');
    if (model) args.push('--model', model);
    if (temperature) args.push('--temperature', temperature);
    if (minWords) args.push('--min-words', minWords);
    if (maxWords) args.push('--max-words', maxWords);
    if (style) args.push('--style', style);
    if (tone) args.push('--tone', tone);
    if (delay) args.push('--delay', delay);
    
    console.log('Executing command:', args.join(' '));
    
    // Start a process to run the shell script
    const process = spawn('bash', ['-c', args.join(' ')], {
        cwd: __dirname,
        shell: true
    });
    
    let outputData = '';
    let errorData = '';
    
    // Collect output
    process.stdout.on('data', (data) => {
        const chunk = data.toString();
        console.log(chunk);
        outputData += chunk;
    });
    
    process.stderr.on('data', (data) => {
        const chunk = data.toString();
        console.error(chunk);
        errorData += chunk;
    });
    
    // Handle process completion
    process.on('close', (code) => {
        console.log(`Process exited with code ${code}`);
        
        // Try to find the generated output file path from the output
        let outputFilePath = '';
        const outlineMatch = outputData.match(/saved to: ([^\n]+)/);
        if (outlineMatch && outlineMatch[1]) {
            outputFilePath = outlineMatch[1].trim();
        }
        
        res.json({
            success: code === 0,
            output: outputData,
            error: errorData,
            outputFile: outputFilePath,
            exitCode: code
        });
    });
});

// API endpoint to get the list of generated books
app.get('/api/books', (req, res) => {
    const outputDir = path.join(__dirname, '../book_outputs');
    
    fs.readdir(outputDir, (err, files) => {
        if (err) {
            return res.status(500).json({ success: false, message: 'Error reading output directory', error: err });
        }
        
        const books = files
            .filter(file => file.startsWith('book_outline_'))
            .map(file => {
                // Extract date from filename
                const match = file.match(/book_outline_(\d{8}_\d{6})\.md/);
                const timestamp = match ? match[1] : '';
                
                return {
                    filename: file,
                    path: path.join('book_outputs', file),
                    timestamp: timestamp,
                    date: timestamp ? `${timestamp.slice(0, 4)}-${timestamp.slice(4, 6)}-${timestamp.slice(6, 8)} ${timestamp.slice(9, 11)}:${timestamp.slice(11, 13)}:${timestamp.slice(13, 15)}` : ''
                };
            })
            .sort((a, b) => b.timestamp.localeCompare(a.timestamp)); // Sort by newest first
            
        res.json({ success: true, books });
    });
});

// API endpoint to get the content of a specific book
app.get('/api/book/:filename', (req, res) => {
    const filePath = path.join(__dirname, '../book_outputs', req.params.filename);
    
    fs.readFile(filePath, 'utf8', (err, data) => {
        if (err) {
            return res.status(404).json({ success: false, message: 'Book not found', error: err });
        }
        
        res.json({ success: true, content: data });
    });
});

// Start the server
app.listen(port, () => {
    console.log(`Book Generator Web UI running at http://localhost:${port}`);
});
