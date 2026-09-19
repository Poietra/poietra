import { Component } from 'react';

// React's class lifecycle is an interop boundary. State, recovery and rendering
// are callbacks from MoonBit, not application logic embedded in this adapter.
export const createBoundary = (initialState, recover, render) => class extends Component {
  state = initialState;
  static getDerivedStateFromError(error) { return recover(error); }
  render() { return render(this.props, this.state); }
};
