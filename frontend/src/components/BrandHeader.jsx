import React from 'react';

const BrandHeader = () => {
  return (
    <header style={styles.header}>
      <h1 data-test="brand-header-title" style={styles.title}>JasaSane Corp</h1>
    </header>
  );
};

const styles = {
  header: {
    width: '100%',
    backgroundColor: '#007bff',
    padding: '18px 24px',
    boxSizing: 'border-box',
    textAlign: 'center',
  },
  title: {
    margin: '0',
    color: 'white',
    fontSize: '22px',
    fontWeight: 'bold',
    letterSpacing: '0.5px',
  },
};

export default BrandHeader;