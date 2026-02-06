# GitHub Copilot Instructions for MTG Card Importer Backend

## Project Overview

This is a **Node.js backend service** that acts as a middleware between Tabletop Simulator and Scryfall's Magic: The Gathering API. The service:
- Proxies and rate-limits Scryfall API requests
- Converts card data to Tabletop Simulator's CardCustom format
- Supports both API mode (direct Scryfall calls) and bulk data mode (in-memory cache)
- Handles deck imports in multiple formats (Arena, Moxfield, Archidekt, etc.)
- Optimized for high concurrency (500+ users) using Node.js clustering

**Primary Tech Stack:**
- Node.js with Express.js
- Jest for testing
- ESLint (ES6+ with CommonJS modules)
- Docker for deployment
- No build step required (pure JavaScript)

## Critical Requirements

### Scryfall API Compliance
⚠️ **ALWAYS respect Scryfall API guidelines:**
- Enforce rate limiting (default: 100ms between requests, configurable via `SCRYFALL_DELAY`)
- Include proper User-Agent and Accept headers in all API requests
- Respect `Retry-After` headers for 429 responses
- Prefer bulk data mode for self-hosted deployments to minimize API calls
- See `SCRYFALL_API_COMPLIANCE.md` for detailed requirements

### Security Requirements
- **NEVER** introduce security vulnerabilities, especially:
  - Command injection in shell commands
  - Path traversal in file operations
  - XSS vulnerabilities in user input handling
  - Unvalidated URL redirects or SSRF attacks
- **ALWAYS** validate user input for:
  - Card back URLs (must be from allowed domains: Steam CDN, Imgur)
  - Search queries (max length: 10KB)
  - Deck sizes (max: 500 cards by default)
  - Scryfall proxy parameters (block dangerous filters)

### No Breaking Changes
- **DO NOT** modify working functionality without explicit user request
- **DO NOT** remove existing API endpoints or change their behavior
- **DO NOT** alter Scryfall API compliance measures
- **DO NOT** change the clustering behavior or performance optimizations

## Code Conventions

### Style and Patterns
- Use **CommonJS modules** (`require`/`module.exports`), not ES6 modules
- Use **async/await** for asynchronous operations (no raw Promises or callbacks)
- Use **functional programming** patterns where appropriate
- Prefer **const** over **let**, never use **var**
- Use descriptive variable names (no single-letter vars except in loops)
- **No TypeScript** - this is a pure JavaScript project

### Error Handling
- Always use try-catch blocks for async operations
- Return proper HTTP status codes (404 for not found, 400 for validation, 500 for server errors)
- Log errors with context using `console.error()`
- Include descriptive error messages in responses

### Code Organization
- Keep route handlers in `server.js`
- Utility functions belong in `lib/` directory:
  - `lib/scryfall.js` - Scryfall API client
  - `lib/bulk-data.js` - Bulk data management
  - `lib/cluster-config.js` - Clustering configuration
- Tests go in `__tests__/` directory

### Naming Conventions
- Use camelCase for variables and functions
- Use UPPER_CASE for constants
- Use kebab-case for file names
- Route parameter names should be descriptive (e.g., `:name`, `:set`, `:number`)

## Build, Test, and Validation

### Essential Commands
```bash
# Install dependencies
npm install

# Run linter (MUST pass before committing)
npm run lint

# Fix linting issues automatically
npm run lint:fix

# Run all tests (MUST pass before committing)
npm test

# Run tests in watch mode (for development)
npm run test:watch

# Run tests with coverage
npm run test:coverage

# Start server (development, single process)
npm start

# Start server (development, with auto-reload)
npm run dev

# Start server (production, with clustering)
npm run start:cluster
```

### Testing Requirements
- **ALWAYS** run `npm test` before committing changes
- **ALWAYS** run `npm run lint` before committing changes
- Write tests for new endpoints and features
- Place tests in `__tests__/` directory with `.test.js` suffix
- Use Jest framework and Supertest for API testing
- Mock external API calls in tests (don't hit real Scryfall API)
- Aim for meaningful test coverage, especially for:
  - New endpoints
  - Input validation
  - Error handling
  - Security-critical code

### Testing Patterns
- Use `describe()` blocks to group related tests
- Use descriptive test names: `it('should return 404 when card not found')`
- Use `beforeAll()` and `afterAll()` for setup/teardown
- Mock bulk data when testing bulk mode features
- Test both success and error cases

## Important Files and Documentation

### Configuration Files
- `.env.example` - Environment variable template
- `eslint.config.js` - ESLint configuration
- `jest.config.js` - Jest test configuration
- `Dockerfile` - Docker container configuration
- `Procfile` - Heroku deployment configuration

### Documentation Files (READ THESE)
- `README.md` - Main documentation
- `SCRYFALL_API_COMPLIANCE.md` - API compliance requirements
- `PERFORMANCE_GUIDE.md` - Performance tuning and benchmarks
- `CUSTOM_IMAGE_PROXY_GUIDE.md` - Custom card image feature

## Key Features and Behavior

### Bulk Data Mode
- When `USE_BULK_DATA=true`, loads Scryfall Oracle bulk data (~500MB) into memory
- Downloads bulk file once, caches on disk for subsequent restarts
- Provides instant responses (no API calls for most queries)
- Requires more RAM but handles high concurrency better
- **IMPORTANT:** Only the master process should manage bulk data updates

### Clustering Mode
- When `WORKERS=auto` or `WORKERS > 1`, uses Node.js clustering
- Each worker is a separate process with its own event loop
- In bulk mode, only master loads and updates bulk data, workers query it via IPC
- Workers share the listening socket (load balanced by OS)
- Memory usage: ~700MB per worker in bulk mode

### Random Card Endpoint
- Automatically excludes non-playable cards (tokens, emblems, art cards, test cards, etc.)
- Deduplicates by oracle_id to prevent reprints from skewing results
- Supports filtering via `?q=` parameter
- Supports count via `?count=` parameter

### Deck Building
- Supports multiple decklist formats (Arena, Moxfield, Archidekt, plain text, etc.)
- Max deck size: 500 cards (configurable via `MAX_DECK_SIZE`)
- Returns NDJSON (one TTS card object per line)
- POST `/deck/parse` validates decklist without building TTS objects

## Common Pitfalls to Avoid

1. **Don't add duplicate bulk data update timers** - Only master process should manage updates
2. **Don't bypass rate limiting** - Always use the rate limiter middleware
3. **Don't hardcode URLs** - Use environment variables for configurable values
4. **Don't skip input validation** - Always validate user input before processing
5. **Don't ignore cache size limits** - Respect `MAX_CACHE_SIZE` to prevent memory leaks
6. **Don't use synchronous file operations** - Use async/await for all I/O
7. **Don't introduce new dependencies lightly** - Discuss with maintainers first

## Dependencies and Libraries

### Core Dependencies
- `express` - Web framework
- `axios` - HTTP client for Scryfall API
- `cors` - CORS middleware
- `compression` - Response compression
- `express-rate-limit` - Rate limiting
- `dotenv` - Environment variable management

### Development Dependencies
- `jest` - Testing framework
- `supertest` - HTTP assertion library
- `eslint` - Linting
- `nodemon` - Auto-reload for development

### Dependency Management
- Use `npm install <package>` to add dependencies
- Use `npm install --save-dev <package>` for dev dependencies
- Update `package.json` and commit both `package.json` and `package-lock.json`
- **Check for security vulnerabilities** before adding new dependencies

## Deployment Considerations

### Environment Variables
Must be configured for production:
- `NODE_ENV=production` (required for optimal performance)
- `USE_BULK_DATA=true` (recommended for self-hosted)
- `WORKERS=auto` (recommended for production)
- `PORT=3000` (default)
- `MAX_CACHE_SIZE=5000` (default)
- `SCRYFALL_DELAY=100` (default)
- `BULK_DATA_PATH=/app/data` (for Docker)

### Docker Deployment
- Uses multi-stage build (kept lightweight)
- Runs as non-root user for security
- Exposes port 3000
- Mounts volume at `/app/data` for bulk data cache
- Uses `npm run start:cluster` by default

### Memory Requirements
- API mode: ~100-200MB per worker
- Bulk mode: ~700MB per worker (~500MB bulk data + ~200MB overhead)
- Auto-scaling caps workers based on available memory

## Questions to Ask Before Making Changes

1. Will this change affect Scryfall API compliance?
2. Could this introduce a security vulnerability?
3. Will this break existing API endpoints or expected behavior?
4. Does this require testing with both API mode and bulk data mode?
5. Does this affect clustering behavior or inter-process communication?
6. Have I tested with both single-process and multi-process modes?
7. Have I updated relevant documentation files?

## Resources

- [Scryfall API Documentation](https://scryfall.com/docs/api)
- [Tabletop Simulator Custom Objects](https://kb.tabletopsimulator.com/custom-content/custom-object/)
- [Express.js Documentation](https://expressjs.com/)
- [Jest Documentation](https://jestjs.io/)

## Contact and Contribution

- Main branch: `main`
- Use feature branches for new work
- Run lint and tests before opening PRs
- Follow existing code style and patterns
- Include tests for new features
- Update documentation when adding features or changing behavior
