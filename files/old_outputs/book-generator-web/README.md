# Book Generator Web UI

A web-based user interface for the AI book generation scripts.

## Features

- Generate book outlines and full books with an intuitive UI
- Configure generation parameters (model, temperature, writing style, etc.)
- View and browse previously generated books
- Preview book content in markdown format

## Prerequisites

- Node.js (v14 or higher)
- npm
- Access to the book generator shell scripts

## Installation

1. Clone this repository or navigate to the book-generator-web directory
2. Install dependencies:

```bash
npm install
```

## Usage

### Development Mode

Run the application in development mode with auto-reload:

```bash
npm run dev
# or
npx nodemon app.js
```

### Production Mode

Run the application in production mode:

```bash
npm start
# or
node app.js
```

## Accessing the UI

Open your web browser and navigate to:
http://localhost:3000

## Configuration

The application is pre-configured to work with the book generation scripts in the parent directory. No additional configuration is needed unless you want to modify the port or other settings.

## Interface Guide

1. **Basic Tab**
   - Enter the book topic, genre, and target audience
   - Choose whether to generate just the outline or the full book
   - Select a preset style (creative, technical, fiction, business)

2. **Advanced Tab**
   - Configure the model and generation parameters
   - Adjust word count, writing style, tone, and other settings

3. **Book List**
   - View and browse previously generated books
   - Click on a book to preview its content

## Adding New Features

Feel free to modify this application to add new features or improve existing ones. Some ideas:

- Add user authentication
- Add the ability to edit and regenerate specific chapters
- Add export options (PDF, EPUB, etc.)
- Add a progress indicator for the generation process

## License

ISC
