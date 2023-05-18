// Specify the database name and output file name
const databaseName = 'your_database_name';
const outputFile = 'documents.json';

// Import the fs module
const fs = require('fs');

// Connect to the MongoDB instance
const connection = new Mongo();
const db = connection.getDB(databaseName);

// Find all the documents where "enabled" is true
// FIXME: the AS_schedules doesnt appear to have an enabled entry. 
// FIXME: so the api must be returning that value from somewhere else. need to locate.
const documentsToUpdate = db.AS_schedules.find({ enabled: true }).toArray();

// Update the "enabled" value to false for all the retrieved documents
db.AS_schedules.updateMany({ enabled: true }, { $set: { enabled: false } });

// Write the documentsToUpdate array to a JSON file
fs.writeFileSync(outputFile, JSON.stringify(documentsToUpdate, null, 2));
